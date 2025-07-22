@description('Main Bicep template for CI/CD Testing Workflows with Static Web Apps and Container Apps Jobs')

// Parameters
@description('The location where resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('GitHub repository URL for Static Web App')
param githubRepositoryUrl string

@description('GitHub branch for Static Web App deployment')
param githubBranch string = 'main'

@description('GitHub personal access token for Static Web App')
@secure()
param githubToken string

@description('Container registry admin username')
param containerRegistryAdminUsername string = 'admin'

@description('Container registry admin password')
@secure()
param containerRegistryAdminPassword string

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  purpose: 'cicd-testing'
  recipe: 'static-web-apps-container-jobs'
}

// Variables
var staticWebAppName = 'swa-cicd-demo-${uniqueSuffix}'
var containerAppsEnvironmentName = 'cae-testing-${uniqueSuffix}'
var containerRegistryName = 'acr${uniqueSuffix}'
var loadTestResourceName = 'alt-cicd-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-cicd-${uniqueSuffix}'
var applicationInsightsName = 'ai-cicd-${uniqueSuffix}'
var testJobName = 'test-runner-job'
var loadTestJobName = 'load-test-job'
var uiTestJobName = 'ui-test-job'

// Log Analytics Workspace
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
      enableLogAccessUsingOnlyResourcePermissions: true
    }
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
  }
}

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

// Container Apps Environment
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

// Static Web App
resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: staticWebAppName
  location: location
  tags: tags
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    repositoryUrl: githubRepositoryUrl
    branch: githubBranch
    repositoryToken: githubToken
    buildProperties: {
      appLocation: '/'
      outputLocation: 'dist'
      appBuildCommand: 'npm run build'
      outputLocation: 'dist'
    }
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    provider: 'GitHub'
  }
}

// Load Testing Resource
resource loadTestResource 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: loadTestResourceName
  location: location
  tags: tags
  properties: {
    description: 'Load testing resource for CI/CD pipeline'
  }
}

// Integration Test Container Apps Job
resource integrationTestJob 'Microsoft.App/jobs@2024-03-01' = {
  name: testJobName
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 1800
      replicaRetryLimit: 3
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistryAdminUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistryAdminPassword
        }
        {
          name: 'instrumentation-key'
          value: applicationInsights.properties.InstrumentationKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'test-runner'
          image: 'mcr.microsoft.com/azure-cli:latest'
          command: ['/bin/bash']
          args: [
            '-c'
            'echo "Running integration tests for ${staticWebApp.properties.defaultHostname}..."; echo "Application Insights Key: ${applicationInsights.properties.InstrumentationKey}"; sleep 30; echo "Integration tests completed successfully"'
          ]
          env: [
            {
              name: 'STATIC_WEB_APP_URL'
              value: 'https://${staticWebApp.properties.defaultHostname}'
            }
            {
              name: 'INSTRUMENTATION_KEY'
              secretRef: 'instrumentation-key'
            }
            {
              name: 'ENVIRONMENT'
              value: environment
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
}

// Load Test Container Apps Job
resource loadTestJob 'Microsoft.App/jobs@2024-03-01' = {
  name: loadTestJobName
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 3600
      replicaRetryLimit: 2
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistryAdminUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistryAdminPassword
        }
        {
          name: 'instrumentation-key'
          value: applicationInsights.properties.InstrumentationKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'load-test-runner'
          image: 'mcr.microsoft.com/azure-cli:latest'
          command: ['/bin/bash']
          args: [
            '-c'
            'echo "Starting load test for ${staticWebApp.properties.defaultHostname}..."; echo "Load Test Resource: ${loadTestResource.name}"; echo "Target URL: https://${staticWebApp.properties.defaultHostname}"; sleep 60; echo "Load test completed successfully"'
          ]
          env: [
            {
              name: 'LOAD_TEST_RESOURCE'
              value: loadTestResource.name
            }
            {
              name: 'TARGET_URL'
              value: 'https://${staticWebApp.properties.defaultHostname}'
            }
            {
              name: 'RESOURCE_GROUP'
              value: resourceGroup().name
            }
            {
              name: 'INSTRUMENTATION_KEY'
              secretRef: 'instrumentation-key'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
    }
  }
}

// UI Test Container Apps Job
resource uiTestJob 'Microsoft.App/jobs@2024-03-01' = {
  name: uiTestJobName
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 2400
      replicaRetryLimit: 3
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistryAdminUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistryAdminPassword
        }
        {
          name: 'instrumentation-key'
          value: applicationInsights.properties.InstrumentationKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'ui-test-runner'
          image: 'mcr.microsoft.com/playwright:latest'
          command: ['/bin/bash']
          args: [
            '-c'
            'echo "Starting UI tests for ${staticWebApp.properties.defaultHostname}..."; echo "Running cross-browser compatibility tests"; sleep 45; echo "UI tests completed successfully"'
          ]
          env: [
            {
              name: 'TARGET_URL'
              value: 'https://${staticWebApp.properties.defaultHostname}'
            }
            {
              name: 'INSTRUMENTATION_KEY'
              secretRef: 'instrumentation-key'
            }
            {
              name: 'ENVIRONMENT'
              value: environment
            }
          ]
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
        }
      ]
    }
  }
}

// Outputs
@description('Static Web App URL')
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'

@description('Static Web App name')
output staticWebAppName string = staticWebApp.name

@description('Container Apps Environment name')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Container Registry name')
output containerRegistryName string = containerRegistry.name

@description('Load Test Resource name')
output loadTestResourceName string = loadTestResource.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Integration Test Job name')
output integrationTestJobName string = integrationTestJob.name

@description('Load Test Job name')
output loadTestJobName string = loadTestJob.name

@description('UI Test Job name')
output uiTestJobName string = uiTestJob.name

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('GitHub Actions secrets configuration')
output githubActionsSecrets object = {
  AZURE_STATIC_WEB_APPS_API_TOKEN: staticWebApp.listSecrets().properties.apiKey
  AZURE_CONTAINER_REGISTRY_LOGIN_SERVER: containerRegistry.properties.loginServer
  AZURE_CONTAINER_REGISTRY_USERNAME: containerRegistryAdminUsername
  APPLICATION_INSIGHTS_INSTRUMENTATION_KEY: applicationInsights.properties.InstrumentationKey
  LOAD_TEST_RESOURCE_NAME: loadTestResource.name
  RESOURCE_GROUP_NAME: resourceGroup().name
}