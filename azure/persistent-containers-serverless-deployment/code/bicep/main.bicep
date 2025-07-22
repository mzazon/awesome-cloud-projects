@description('Main Bicep template for Persistent Containers with Serverless Deployment')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name for all resources')
param baseName string = 'stateful-containers'

@description('Random suffix for unique resource names')
param randomSuffix string = uniqueString(resourceGroup().id)

@description('Azure Files share quota in GB')
@minValue(1)
@maxValue(102400)
param fileShareQuotaGb int = 100

@description('PostgreSQL database password')
@secure()
param postgresPassword string

@description('PostgreSQL database name')
param postgresDbName string = 'appdb'

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Container registry SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySku string = 'Basic'

@description('Enable container registry admin user')
param enableRegistryAdmin bool = true

@description('Container CPU allocation')
@minValue(0.5)
@maxValue(4.0)
param containerCpuCores decimal = 1.0

@description('Container memory allocation in GB')
@minValue(0.5)
@maxValue(16.0)
param containerMemoryGb decimal = 2.0

@description('Environment tag')
param environmentTag string = 'demo'

@description('Purpose tag')
param purposeTag string = 'recipe'

// Variables
var storageAccountName = 'st${baseName}${randomSuffix}'
var containerRegistryName = 'acr${baseName}${randomSuffix}'
var logAnalyticsWorkspaceName = 'log-${baseName}-${randomSuffix}'
var fileShareName = 'containerdata'
var postgresContainerName = 'postgres-stateful'
var appContainerName = 'app-stateful'
var workerContainerName = 'worker-stateful'
var monitoredAppContainerName = 'monitored-app'

// Common tags
var commonTags = {
  environment: environmentTag
  purpose: purposeTag
  solution: 'stateful-containers'
  managedBy: 'bicep'
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: commonTags
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

// Storage Account for Azure Files
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    largeFileSharesState: 'Enabled'
    encryption: {
      services: {
        file: {
          enabled: true
        }
        blob: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Azure Files Service
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Azure Files Share
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: fileShareName
  parent: fileService
  properties: {
    shareQuota: fileShareQuotaGb
    enabledProtocols: 'SMB'
    accessTier: 'Hot'
  }
}

// Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: containerRegistryName
  location: location
  tags: commonTags
  sku: {
    name: containerRegistrySku
  }
  properties: {
    adminUserEnabled: enableRegistryAdmin
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

// PostgreSQL Container Instance
resource postgresContainer 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: postgresContainerName
  location: location
  tags: commonTags
  properties: {
    containers: [
      {
        name: 'postgres'
        properties: {
          image: 'postgres:13'
          ports: [
            {
              port: 5432
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: containerCpuCores
              memoryInGB: containerMemoryGb
            }
          }
          environmentVariables: [
            {
              name: 'POSTGRES_PASSWORD'
              secureValue: postgresPassword
            }
            {
              name: 'POSTGRES_DB'
              value: postgresDbName
            }
            {
              name: 'PGDATA'
              value: '/var/lib/postgresql/data/pgdata'
            }
          ]
          volumeMounts: [
            {
              name: 'postgres-data'
              mountPath: '/var/lib/postgresql/data'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Always'
    volumes: [
      {
        name: 'postgres-data'
        azureFile: {
          shareName: fileShareName
          storageAccountName: storageAccountName
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
    ]
  }
}

// Application Container Instance
resource appContainer 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: appContainerName
  location: location
  tags: commonTags
  properties: {
    containers: [
      {
        name: 'nginx-app'
        properties: {
          image: 'nginx:alpine'
          ports: [
            {
              port: 80
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: 0.5
              memoryInGB: 1.0
            }
          }
          volumeMounts: [
            {
              name: 'app-data'
              mountPath: '/usr/share/nginx/html'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Public'
      ports: [
        {
          port: 80
          protocol: 'TCP'
        }
      ]
      dnsNameLabel: 'stateful-app-${randomSuffix}'
    }
    volumes: [
      {
        name: 'app-data'
        azureFile: {
          shareName: fileShareName
          storageAccountName: storageAccountName
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
    ]
  }
}

// Worker Container Instance
resource workerContainer 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: workerContainerName
  location: location
  tags: commonTags
  properties: {
    containers: [
      {
        name: 'worker'
        properties: {
          image: 'alpine:latest'
          command: [
            'sh'
            '-c'
            'mkdir -p /shared/logs && while true; do echo "Worker processing at $(date)" >> /shared/logs/worker.log; sleep 60; done'
          ]
          resources: {
            requests: {
              cpu: 0.5
              memoryInGB: 0.5
            }
          }
          volumeMounts: [
            {
              name: 'shared-data'
              mountPath: '/shared'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Always'
    volumes: [
      {
        name: 'shared-data'
        azureFile: {
          shareName: fileShareName
          storageAccountName: storageAccountName
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
    ]
  }
}

// Monitored Application Container Instance with Log Analytics
resource monitoredAppContainer 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: monitoredAppContainerName
  location: location
  tags: commonTags
  properties: {
    containers: [
      {
        name: 'monitored-nginx'
        properties: {
          image: 'nginx:alpine'
          ports: [
            {
              port: 80
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: 0.5
              memoryInGB: 1.0
            }
          }
          volumeMounts: [
            {
              name: 'monitored-app-data'
              mountPath: '/usr/share/nginx/html'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Public'
      ports: [
        {
          port: 80
          protocol: 'TCP'
        }
      ]
      dnsNameLabel: 'monitored-app-${randomSuffix}'
    }
    diagnostics: {
      logAnalytics: {
        workspaceId: logAnalyticsWorkspace.properties.customerId
        workspaceKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    volumes: [
      {
        name: 'monitored-app-data'
        azureFile: {
          shareName: fileShareName
          storageAccountName: storageAccountName
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
    ]
  }
}

// Outputs
@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account key')
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('Azure Files share name')
output fileShareName string = fileShareName

@description('Container registry name')
output containerRegistryName string = containerRegistry.name

@description('Container registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Container registry admin username')
output containerRegistryUsername string = containerRegistry.listCredentials().username

@description('Container registry admin password')
output containerRegistryPassword string = containerRegistry.listCredentials().passwords[0].value

@description('PostgreSQL container FQDN')
output postgresContainerFqdn string = postgresContainer.properties.ipAddress.fqdn

@description('Application container FQDN')
output appContainerFqdn string = appContainer.properties.ipAddress.fqdn

@description('Monitored application container FQDN')
output monitoredAppContainerFqdn string = monitoredAppContainer.properties.ipAddress.fqdn

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment location')
output deploymentLocation string = location

@description('All container endpoints')
output containerEndpoints object = {
  app: 'http://${appContainer.properties.ipAddress.fqdn}'
  monitoredApp: 'http://${monitoredAppContainer.properties.ipAddress.fqdn}'
  postgres: postgresContainer.properties.ipAddress.fqdn
}

@description('Storage connection information')
output storageInfo object = {
  accountName: storageAccount.name
  shareQuota: fileShareQuotaGb
  shareName: fileShareName
  endpoint: storageAccount.properties.primaryEndpoints.file
}

@description('Registry connection information')
output registryInfo object = {
  name: containerRegistry.name
  loginServer: containerRegistry.properties.loginServer
  adminEnabled: enableRegistryAdmin
}