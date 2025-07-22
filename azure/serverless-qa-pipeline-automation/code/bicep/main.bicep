@description('The location where all resources will be deployed')
param location string = resourceGroup().location

@description('Prefix for all resource names')
param resourcePrefix string = 'qa-pipeline'

@description('Environment suffix for resource names')
param environmentSuffix string = uniqueString(resourceGroup().id)

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'qa-pipeline'
  environment: 'demo'
  recipe: 'implementing-automated-quality-assurance-pipelines'
}

@description('Container Apps Environment configuration')
param containerAppsEnvironment object = {
  name: '${resourcePrefix}-cae-${environmentSuffix}'
  workloadProfiles: [
    {
      name: 'Consumption'
      workloadProfileType: 'Consumption'
    }
  ]
}

@description('Log Analytics workspace configuration')
param logAnalyticsWorkspace object = {
  name: '${resourcePrefix}-law-${environmentSuffix}'
  sku: 'PerGB2018'
  retentionInDays: 30
}

@description('Storage account configuration')
param storageAccount object = {
  name: replace('${resourcePrefix}st${environmentSuffix}', '-', '')
  sku: 'Standard_LRS'
  kind: 'StorageV2'
  containers: [
    'load-test-scripts'
    'monitoring-templates'
    'test-results'
    'test-artifacts'
  ]
}

@description('Azure Load Testing configuration')
param loadTesting object = {
  name: '${resourcePrefix}-lt-${environmentSuffix}'
}

@description('Container Apps Jobs configuration')
param containerAppsJobs object = {
  unitTest: {
    name: 'unit-test-job'
    triggerType: 'Manual'
    replicaTimeout: 1800
    replicaRetryLimit: 3
    parallelism: 3
    replicaCompletionCount: 1
    image: 'mcr.microsoft.com/dotnet/sdk:7.0'
    cpu: '1.0'
    memory: '2Gi'
    command: ['/bin/bash']
    args: ['-c', 'echo "Running unit tests..."; sleep 10; echo "Unit tests completed successfully"']
  }
  integrationTest: {
    name: 'integration-test-job'
    triggerType: 'Manual'
    replicaTimeout: 3600
    replicaRetryLimit: 2
    parallelism: 2
    replicaCompletionCount: 1
    image: 'mcr.microsoft.com/dotnet/sdk:7.0'
    cpu: '1.5'
    memory: '3Gi'
    command: ['/bin/bash']
    args: ['-c', 'echo "Running integration tests with timeout: $TIMEOUT"; sleep 15; echo "Integration tests completed"']
    environmentVariables: [
      {
        name: 'TEST_TYPE'
        value: 'integration'
      }
      {
        name: 'TIMEOUT'
        value: '3600'
      }
    ]
  }
  performanceTest: {
    name: 'performance-test-job'
    triggerType: 'Manual'
    replicaTimeout: 7200
    replicaRetryLimit: 1
    parallelism: 1
    replicaCompletionCount: 1
    image: 'mcr.microsoft.com/azure-cli:latest'
    cpu: '0.5'
    memory: '1Gi'
    command: ['/bin/bash']
    args: ['-c', 'echo "Starting load test orchestration"; echo "Load test: $LOAD_TEST_NAME"; sleep 30; echo "Performance test orchestration completed"']
    environmentVariables: [
      {
        name: 'LOAD_TEST_NAME'
        value: loadTesting.name
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
    ]
  }
  securityTest: {
    name: 'security-test-job'
    triggerType: 'Manual'
    replicaTimeout: 2400
    replicaRetryLimit: 2
    parallelism: 1
    replicaCompletionCount: 1
    image: 'mcr.microsoft.com/dotnet/sdk:7.0'
    cpu: '1.0'
    memory: '2Gi'
    command: ['/bin/bash']
    args: ['-c', 'echo "Starting security scan: $SECURITY_SCAN_TYPE"; sleep 20; echo "Security scan completed - format: $REPORT_FORMAT"']
    environmentVariables: [
      {
        name: 'SECURITY_SCAN_TYPE'
        value: 'full'
      }
      {
        name: 'REPORT_FORMAT'
        value: 'json'
      }
    ]
  }
}

@description('Application Insights configuration')
param applicationInsights object = {
  name: '${resourcePrefix}-ai-${environmentSuffix}'
  applicationType: 'web'
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspace.name
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspace.sku
    }
    retentionInDays: logAnalyticsWorkspace.retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsights.name
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: applicationInsights.applicationType
    WorkspaceResourceId: logAnalytics.id
  }
}

// Storage Account
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccount.name
  location: location
  tags: tags
  sku: {
    name: storageAccount.sku
  }
  kind: storageAccount.kind
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Storage Containers
resource storageContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for container in storageAccount.containers: {
  name: '${storage.name}/default/${container}'
  properties: {
    publicAccess: 'None'
  }
}]

// Container Apps Environment
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppsEnvironment.name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    workloadProfiles: containerAppsEnvironment.workloadProfiles
  }
}

// Azure Load Testing
resource loadTestingResource 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: loadTesting.name
  location: location
  tags: tags
  properties: {
    description: 'Load testing resource for automated QA pipeline'
  }
}

// Container Apps Jobs
resource unitTestJob 'Microsoft.App/jobs@2023-05-01' = {
  name: containerAppsJobs.unitTest.name
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnv.id
    configuration: {
      triggerType: containerAppsJobs.unitTest.triggerType
      replicaTimeout: containerAppsJobs.unitTest.replicaTimeout
      replicaRetryLimit: containerAppsJobs.unitTest.replicaRetryLimit
      manualTriggerConfig: {
        parallelism: containerAppsJobs.unitTest.parallelism
        replicaCompletionCount: containerAppsJobs.unitTest.replicaCompletionCount
      }
    }
    template: {
      containers: [
        {
          name: 'unit-test-container'
          image: containerAppsJobs.unitTest.image
          command: containerAppsJobs.unitTest.command
          args: containerAppsJobs.unitTest.args
          resources: {
            cpu: json(containerAppsJobs.unitTest.cpu)
            memory: containerAppsJobs.unitTest.memory
          }
        }
      ]
    }
  }
}

resource integrationTestJob 'Microsoft.App/jobs@2023-05-01' = {
  name: containerAppsJobs.integrationTest.name
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnv.id
    configuration: {
      triggerType: containerAppsJobs.integrationTest.triggerType
      replicaTimeout: containerAppsJobs.integrationTest.replicaTimeout
      replicaRetryLimit: containerAppsJobs.integrationTest.replicaRetryLimit
      manualTriggerConfig: {
        parallelism: containerAppsJobs.integrationTest.parallelism
        replicaCompletionCount: containerAppsJobs.integrationTest.replicaCompletionCount
      }
    }
    template: {
      containers: [
        {
          name: 'integration-test-container'
          image: containerAppsJobs.integrationTest.image
          command: containerAppsJobs.integrationTest.command
          args: containerAppsJobs.integrationTest.args
          env: containerAppsJobs.integrationTest.environmentVariables
          resources: {
            cpu: json(containerAppsJobs.integrationTest.cpu)
            memory: containerAppsJobs.integrationTest.memory
          }
        }
      ]
    }
  }
}

resource performanceTestJob 'Microsoft.App/jobs@2023-05-01' = {
  name: containerAppsJobs.performanceTest.name
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnv.id
    configuration: {
      triggerType: containerAppsJobs.performanceTest.triggerType
      replicaTimeout: containerAppsJobs.performanceTest.replicaTimeout
      replicaRetryLimit: containerAppsJobs.performanceTest.replicaRetryLimit
      manualTriggerConfig: {
        parallelism: containerAppsJobs.performanceTest.parallelism
        replicaCompletionCount: containerAppsJobs.performanceTest.replicaCompletionCount
      }
    }
    template: {
      containers: [
        {
          name: 'performance-test-container'
          image: containerAppsJobs.performanceTest.image
          command: containerAppsJobs.performanceTest.command
          args: containerAppsJobs.performanceTest.args
          env: containerAppsJobs.performanceTest.environmentVariables
          resources: {
            cpu: json(containerAppsJobs.performanceTest.cpu)
            memory: containerAppsJobs.performanceTest.memory
          }
        }
      ]
    }
  }
}

resource securityTestJob 'Microsoft.App/jobs@2023-05-01' = {
  name: containerAppsJobs.securityTest.name
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnv.id
    configuration: {
      triggerType: containerAppsJobs.securityTest.triggerType
      replicaTimeout: containerAppsJobs.securityTest.replicaTimeout
      replicaRetryLimit: containerAppsJobs.securityTest.replicaRetryLimit
      manualTriggerConfig: {
        parallelism: containerAppsJobs.securityTest.parallelism
        replicaCompletionCount: containerAppsJobs.securityTest.replicaCompletionCount
      }
    }
    template: {
      containers: [
        {
          name: 'security-test-container'
          image: containerAppsJobs.securityTest.image
          command: containerAppsJobs.securityTest.command
          args: containerAppsJobs.securityTest.args
          env: containerAppsJobs.securityTest.environmentVariables
          resources: {
            cpu: json(containerAppsJobs.securityTest.cpu)
            memory: containerAppsJobs.securityTest.memory
          }
        }
      ]
    }
  }
}

// Outputs
@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the Container Apps Environment')
output containerAppsEnvironmentName string = containerAppsEnv.name

@description('The ID of the Container Apps Environment')
output containerAppsEnvironmentId string = containerAppsEnv.id

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalytics.name

@description('The ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalytics.id

@description('The name of the Storage Account')
output storageAccountName string = storage.name

@description('The ID of the Storage Account')
output storageAccountId string = storage.id

@description('The name of the Azure Load Testing resource')
output loadTestingResourceName string = loadTestingResource.name

@description('The ID of the Azure Load Testing resource')
output loadTestingResourceId string = loadTestingResource.id

@description('The name of the Application Insights resource')
output applicationInsightsName string = appInsights.name

@description('The ID of the Application Insights resource')
output applicationInsightsId string = appInsights.id

@description('The instrumentation key for Application Insights')
output applicationInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('The connection string for Application Insights')
output applicationInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Container Apps Job names')
output containerAppsJobNames object = {
  unitTest: unitTestJob.name
  integrationTest: integrationTestJob.name
  performanceTest: performanceTestJob.name
  securityTest: securityTestJob.name
}

@description('Container Apps Job IDs')
output containerAppsJobIds object = {
  unitTest: unitTestJob.id
  integrationTest: integrationTestJob.id
  performanceTest: performanceTestJob.id
  securityTest: securityTestJob.id
}

@description('Storage container names')
output storageContainerNames array = storageAccount.containers

@description('Azure CLI commands for testing the deployment')
output testingCommands object = {
  checkEnvironment: 'az containerapp env show --name ${containerAppsEnv.name} --resource-group ${resourceGroup().name}'
  listJobs: 'az containerapp job list --resource-group ${resourceGroup().name} --output table'
  startUnitTest: 'az containerapp job start --name ${unitTestJob.name} --resource-group ${resourceGroup().name}'
  startIntegrationTest: 'az containerapp job start --name ${integrationTestJob.name} --resource-group ${resourceGroup().name}'
  startPerformanceTest: 'az containerapp job start --name ${performanceTestJob.name} --resource-group ${resourceGroup().name}'
  startSecurityTest: 'az containerapp job start --name ${securityTestJob.name} --resource-group ${resourceGroup().name}'
  checkLoadTesting: 'az load show --name ${loadTestingResource.name} --resource-group ${resourceGroup().name}'
  viewLogs: 'az monitor log-analytics query --workspace ${logAnalytics.properties.customerId} --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(1h) | take 10"'
}