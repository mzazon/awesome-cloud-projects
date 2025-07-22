@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix for all resource names')
param resourcePrefix string = 'selfservice'

@description('Random suffix for resource names to ensure uniqueness')
param randomSuffix string = uniqueString(resourceGroup().id)

@description('Environment type for deployment environments')
param environmentType string = 'Development'

@description('Git repository URL for environment catalog')
param catalogRepoUrl string = 'https://github.com/Azure/deployment-environments'

@description('Git repository branch for environment catalog')
param catalogBranch string = 'main'

@description('Git repository path for environment definitions')
param catalogPath string = '/Environments'

@description('SQL Server administrator login')
@secure()
param sqlAdminLogin string

@description('SQL Server administrator password')
@secure()
param sqlAdminPassword string

@description('Maximum number of dev boxes per user')
param maxDevBoxesPerUser int = 3

@description('Tags to apply to all resources')
param resourceTags object = {
  purpose: 'selfservice-infrastructure'
  environment: 'demo'
  owner: 'platform-team'
}

// Variables for resource names
var devCenterName = '${resourcePrefix}-dc-${randomSuffix}'
var projectName = '${resourcePrefix}-proj-${randomSuffix}'
var catalogName = '${resourcePrefix}-catalog-${randomSuffix}'
var keyVaultName = '${resourcePrefix}-kv-${randomSuffix}'
var logicAppName = '${resourcePrefix}-logic-${randomSuffix}'
var lifecycleLogicAppName = '${resourcePrefix}-lifecycle-${randomSuffix}'
var eventGridTopicName = '${resourcePrefix}-eg-${randomSuffix}'
var storageAccountName = '${resourcePrefix}st${randomSuffix}'
var sqlServerName = '${resourcePrefix}-sql-${randomSuffix}'
var sqlDatabaseName = 'webapp-db'
var webAppName = '${resourcePrefix}-webapp-${randomSuffix}'
var appServicePlanName = '${resourcePrefix}-asp-${randomSuffix}'

// Key Vault for storing secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store SQL credentials in Key Vault
resource sqlLoginSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sqlAdminLogin'
  properties: {
    value: sqlAdminLogin
  }
}

resource sqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sqlAdminPassword'
  properties: {
    value: sqlAdminPassword
  }
}

// Storage Account for Event Grid dead letter
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// Event Grid Topic for deployment events
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: resourceTags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
  }
}

// DevCenter for Azure Deployment Environments
resource devCenter 'Microsoft.DevCenter/devcenters@2024-02-01' = {
  name: devCenterName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// Environment Catalog
resource catalog 'Microsoft.DevCenter/devcenters/catalogs@2024-02-01' = {
  parent: devCenter
  name: catalogName
  properties: {
    gitHub: {
      uri: catalogRepoUrl
      branch: catalogBranch
      path: catalogPath
    }
  }
}

// DevCenter Project
resource project 'Microsoft.DevCenter/projects@2024-02-01' = {
  name: projectName
  location: location
  tags: resourceTags
  properties: {
    devCenterId: devCenter.id
    maxDevBoxesPerUser: maxDevBoxesPerUser
  }
}

// Project Environment Type
resource projectEnvironmentType 'Microsoft.DevCenter/projects/environmentTypes@2024-02-01' = {
  parent: project
  name: environmentType
  properties: {
    status: 'Enabled'
    deploymentTargetId: resourceGroup().id
    creatorRoleAssignment: {
      roles: {
        '4f8fab4f-1852-4a58-a46a-8eaf358af14a': {} // DevCenter Environment User role
      }
    }
  }
}

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: resourceTags
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: resourceTags
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 268435456000 // 250 GB
  }
}

// SQL Server Firewall Rule for Azure Services
resource sqlFirewallRule 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: resourceTags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {
    reserved: false
  }
}

// Web App
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      netFrameworkVersion: 'v6.0'
      metadata: [
        {
          name: 'CURRENT_STACK'
          value: 'dotnet'
        }
      ]
    }
  }
}

// Logic App for approval workflow
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: resourceTags
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                environmentName: {
                  type: 'string'
                }
                projectName: {
                  type: 'string'
                }
                requestedBy: {
                  type: 'string'
                }
                environmentType: {
                  type: 'string'
                }
              }
            }
          }
        }
      }
      actions: {
        'Send_approval_email': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://management.azure.com/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.DevCenter/projects/${projectName}/environments/approve'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              environmentName: '@{triggerBody()?[\'environmentName\']}'
              approved: true
              approvedBy: 'system'
            }
          }
        }
        'Response': {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              message: 'Environment approval processed'
              environmentName: '@{triggerBody()?[\'environmentName\']}'
            }
          }
          runAfter: {
            'Send_approval_email': [
              'Succeeded'
            ]
          }
        }
      }
    }
    parameters: {}
  }
}

// Logic App for lifecycle management
resource lifecycleLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: lifecycleLogicAppName
  location: location
  tags: resourceTags
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        recurrence: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Day'
            interval: 1
            startTime: '2024-01-01T02:00:00Z'
          }
        }
      }
      actions: {
        'Check_environment_expiry': {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://management.azure.com/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.DevCenter/projects/${projectName}/environments'
            headers: {
              'Content-Type': 'application/json'
            }
          }
        }
        'Parse_environments': {
          type: 'ParseJson'
          inputs: {
            content: '@body(\'Check_environment_expiry\')'
            schema: {
              type: 'object'
              properties: {
                value: {
                  type: 'array'
                  items: {
                    type: 'object'
                    properties: {
                      name: {
                        type: 'string'
                      }
                      properties: {
                        type: 'object'
                        properties: {
                          provisioningState: {
                            type: 'string'
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          runAfter: {
            'Check_environment_expiry': [
              'Succeeded'
            ]
          }
        }
      }
    }
    parameters: {}
  }
}

// Event Grid Subscription for deployment events
resource eventGridSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2023-12-15-preview' = {
  parent: eventGridTopic
  name: 'deployment-approval-subscription'
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicAppName, 'manual'), '2019-05-01').value
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.DevCenter.EnvironmentCreated'
        'Microsoft.DevCenter.EnvironmentDeleted'
        'Microsoft.DevCenter.EnvironmentDeploymentCompleted'
      ]
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'deadletter'
      }
    }
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// RBAC assignments for DevCenter managed identity
resource devCenterContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, devCenter.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: devCenter.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC assignment for Web App to access SQL Database
resource webAppSqlReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sqlServer.id, webApp.id, 'db_datareader')
  scope: sqlServer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Service Connector between Web App and SQL Database
resource serviceConnector 'Microsoft.ServiceLinker/linkers@2024-04-01' = {
  scope: webApp
  name: 'sql-connection'
  properties: {
    targetService: {
      type: 'AzureSql'
      resourceId: sqlDatabase.id
    }
    authInfo: {
      authType: 'systemAssignedIdentity'
    }
    clientType: 'dotnet'
    configurationInfo: {
      configurations: {
        AZURE_SQL_CONNECTIONSTRING: 'Server=tcp:${sqlServer.name}.database.windows.net,1433;Database=${sqlDatabase.name};Authentication=Active Directory Managed Identity;'
      }
    }
  }
  dependsOn: [
    webAppSqlReaderAssignment
  ]
}

// Outputs
@description('DevCenter name')
output devCenterName string = devCenter.name

@description('DevCenter resource ID')
output devCenterResourceId string = devCenter.id

@description('Project name')
output projectName string = project.name

@description('Project resource ID')
output projectResourceId string = project.id

@description('Catalog name')
output catalogName string = catalog.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Logic App name for approvals')
output logicAppName string = logicApp.name

@description('Logic App trigger URL')
output logicAppTriggerUrl string = listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicAppName, 'manual'), '2019-05-01').value

@description('Lifecycle Logic App name')
output lifecycleLogicAppName string = lifecycleLogicApp.name

@description('Event Grid Topic name')
output eventGridTopicName string = eventGridTopic.name

@description('Event Grid Topic endpoint')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('SQL Server name')
output sqlServerName string = sqlServer.name

@description('SQL Database name')
output sqlDatabaseName string = sqlDatabase.name

@description('Web App name')
output webAppName string = webApp.name

@description('Web App URL')
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

@description('Service Connector name')
output serviceConnectorName string = serviceConnector.name

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Location')
output location string = location