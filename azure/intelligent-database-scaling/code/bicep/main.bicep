// ==============================================================================
// Intelligent Database Scaling with SQL Hyperscale and Logic Apps
// ==============================================================================
// This template deploys an autonomous database scaling solution using:
// - Azure SQL Database Hyperscale for elastic compute scaling
// - Logic Apps for orchestration and scaling workflows
// - Azure Monitor for performance metrics and alerting
// - Key Vault for secure credential management
// - Log Analytics for comprehensive logging and monitoring
// ==============================================================================

targetScope = 'resourceGroup'

// ==============================================================================
// PARAMETERS
// ==============================================================================

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names (auto-generated if not provided)')
param uniqueSuffix string = uniqueString(resourceGroup().id, deployment().name)

@description('SQL Database administrator username')
@secure()
param sqlAdminUsername string

@description('SQL Database administrator password')
@secure()
@minLength(12)
param sqlAdminPassword string

@description('Initial SQL Database compute capacity (vCores)')
@minValue(2)
@maxValue(80)
param initialDatabaseCapacity int = 2

@description('Maximum SQL Database compute capacity for auto-scaling (vCores)')
@minValue(2)
@maxValue(80)
param maxDatabaseCapacity int = 40

@description('Minimum SQL Database compute capacity for auto-scaling (vCores)')
@minValue(2)
@maxValue(80)
param minDatabaseCapacity int = 2

@description('CPU threshold for scaling up (percentage)')
@minValue(50)
@maxValue(95)
param scaleUpCpuThreshold int = 80

@description('CPU threshold for scaling down (percentage)')
@minValue(10)
@maxValue(50)
param scaleDownCpuThreshold int = 30

@description('Scale up evaluation window (minutes)')
@minValue(1)
@maxValue(60)
param scaleUpWindowMinutes int = 5

@description('Scale down evaluation window (minutes)')
@minValue(5)
@maxValue(120)
param scaleDownWindowMinutes int = 15

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Solution: 'intelligent-database-scaling'
  CreatedBy: 'bicep-template'
}

// ==============================================================================
// VARIABLES
// ==============================================================================

var resourceNames = {
  sqlServer: 'sql-hyperscale-${uniqueSuffix}'
  sqlDatabase: 'hyperscale-db'
  logicApp: 'scaling-logic-app-${uniqueSuffix}'
  keyVault: 'kv-scaling-${uniqueSuffix}'
  logAnalytics: 'la-scaling-${uniqueSuffix}'
  actionGroup: 'ag-scaling-${uniqueSuffix}'
  applicationInsights: 'ai-scaling-${uniqueSuffix}'
}

var alertNames = {
  cpuScaleUp: 'CPU-Scale-Up-Alert'
  cpuScaleDown: 'CPU-Scale-Down-Alert'
}

// ==============================================================================
// EXISTING RESOURCES
// ==============================================================================

// Reference to current user for Key Vault access policies
var currentUserObjectId = '00000000-0000-0000-0000-000000000000' // Will be populated by deployment script

// ==============================================================================
// LOG ANALYTICS WORKSPACE
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
  }
}

// ==============================================================================
// APPLICATION INSIGHTS
// ==============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// ==============================================================================
// KEY VAULT
// ==============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enabledForTemplateDeployment: true
    enabledForDeployment: true
    enabledForDiskEncryption: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Store SQL admin credentials in Key Vault
resource sqlAdminUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-username'
  properties: {
    value: sqlAdminUsername
    contentType: 'text/plain'
  }
}

resource sqlAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: sqlAdminPassword
    contentType: 'text/plain'
  }
}

// Store scaling configuration in Key Vault
resource scalingConfigSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'scaling-config'
  properties: {
    value: string({
      maxCapacity: maxDatabaseCapacity
      minCapacity: minDatabaseCapacity
      scaleUpThreshold: scaleUpCpuThreshold
      scaleDownThreshold: scaleDownCpuThreshold
    })
    contentType: 'application/json'
  }
}

// ==============================================================================
// SQL SERVER AND DATABASE
// ==============================================================================

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: resourceNames.sqlServer
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
  }
}

// Allow Azure services to access SQL Server
resource sqlServerFirewallRule 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Hyperscale database with initial configuration
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: resourceNames.sqlDatabase
  location: location
  tags: tags
  sku: {
    name: 'HS_Gen5'
    tier: 'Hyperscale'
    family: 'Gen5'
    capacity: initialDatabaseCapacity
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: -1 // Unlimited storage for Hyperscale
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    licenseType: 'LicenseIncluded'
    readScale: 'Enabled'
    highAvailabilityReplicaCount: 1
  }
}

// ==============================================================================
// LOGIC APPS WORKFLOW
// ==============================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: resourceNames.logicApp
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        resourceGroup: {
          type: 'string'
          defaultValue: resourceGroup().name
        }
        serverName: {
          type: 'string'
          defaultValue: resourceNames.sqlServer
        }
        databaseName: {
          type: 'string'
          defaultValue: resourceNames.sqlDatabase
        }
        subscriptionId: {
          type: 'string'
          defaultValue: subscription().subscriptionId
        }
        keyVaultName: {
          type: 'string'
          defaultValue: resourceNames.keyVault
        }
        logAnalyticsWorkspaceId: {
          type: 'string'
          defaultValue: logAnalyticsWorkspace.id
        }
      }
      triggers: {
        'When_HTTP_request_received': {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                alertType: {
                  type: 'string'
                }
                resourceId: {
                  type: 'string'
                }
                metricValue: {
                  type: 'number'
                }
                alertContext: {
                  type: 'object'
                }
              }
              required: ['alertType', 'resourceId', 'metricValue']
            }
          }
        }
      }
      actions: {
        'Get_scaling_configuration': {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://@{parameters(\'keyVaultName\')}.vault.azure.net/secrets/scaling-config?api-version=2016-10-01'
            authentication: {
              type: 'ManagedServiceIdentity'
            }
          }
        }
        'Get_current_database_configuration': {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://management.azure.com/subscriptions/@{parameters(\'subscriptionId\')}/resourceGroups/@{parameters(\'resourceGroup\')}/providers/Microsoft.Sql/servers/@{parameters(\'serverName\')}/databases/@{parameters(\'databaseName\')}?api-version=2023-05-01-preview'
            authentication: {
              type: 'ManagedServiceIdentity'
            }
          }
          runAfter: {
            'Get_scaling_configuration': ['Succeeded']
          }
        }
        'Determine_scaling_action': {
          type: 'Switch'
          expression: '@triggerBody()[\'alertType\']'
          cases: {
            'Scale_Up': {
              case: 'CPU-Scale-Up-Alert'
              actions: {
                'Calculate_new_capacity_up': {
                  type: 'Compose'
                  inputs: '@min(add(body(\'Get_current_database_configuration\')[\'properties\'][\'currentSku\'][\'capacity\'], 2), json(body(\'Get_scaling_configuration\')[\'value\'])[\'maxCapacity\'])'
                }
                'Scale_up_database': {
                  type: 'Http'
                  inputs: {
                    method: 'PATCH'
                    uri: 'https://management.azure.com/subscriptions/@{parameters(\'subscriptionId\')}/resourceGroups/@{parameters(\'resourceGroup\')}/providers/Microsoft.Sql/servers/@{parameters(\'serverName\')}/databases/@{parameters(\'databaseName\')}?api-version=2023-05-01-preview'
                    body: {
                      sku: {
                        name: 'HS_Gen5'
                        tier: 'Hyperscale'
                        family: 'Gen5'
                        capacity: '@outputs(\'Calculate_new_capacity_up\')'
                      }
                    }
                    authentication: {
                      type: 'ManagedServiceIdentity'
                    }
                  }
                  runAfter: {
                    'Calculate_new_capacity_up': ['Succeeded']
                  }
                }
              }
            }
            'Scale_Down': {
              case: 'CPU-Scale-Down-Alert'
              actions: {
                'Calculate_new_capacity_down': {
                  type: 'Compose'
                  inputs: '@max(sub(body(\'Get_current_database_configuration\')[\'properties\'][\'currentSku\'][\'capacity\'], 2), json(body(\'Get_scaling_configuration\')[\'value\'])[\'minCapacity\'])'
                }
                'Scale_down_database': {
                  type: 'Http'
                  inputs: {
                    method: 'PATCH'
                    uri: 'https://management.azure.com/subscriptions/@{parameters(\'subscriptionId\')}/resourceGroups/@{parameters(\'resourceGroup\')}/providers/Microsoft.Sql/servers/@{parameters(\'serverName\')}/databases/@{parameters(\'databaseName\')}?api-version=2023-05-01-preview'
                    body: {
                      sku: {
                        name: 'HS_Gen5'
                        tier: 'Hyperscale'
                        family: 'Gen5'
                        capacity: '@outputs(\'Calculate_new_capacity_down\')'
                      }
                    }
                    authentication: {
                      type: 'ManagedServiceIdentity'
                    }
                  }
                  runAfter: {
                    'Calculate_new_capacity_down': ['Succeeded']
                  }
                }
              }
            }
          }
          runAfter: {
            'Get_current_database_configuration': ['Succeeded']
          }
        }
        'Log_scaling_operation': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://@{parameters(\'logAnalyticsWorkspaceId\')}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
            headers: {
              'Log-Type': 'DatabaseScaling'
              'Content-Type': 'application/json'
            }
            body: {
              timestamp: '@utcNow()'
              alertType: '@triggerBody()[\'alertType\']'
              resourceId: '@triggerBody()[\'resourceId\']'
              metricValue: '@triggerBody()[\'metricValue\']'
              previousCapacity: '@body(\'Get_current_database_configuration\')[\'properties\'][\'currentSku\'][\'capacity\']'
              workflowRunId: '@workflow().run.name'
              correlationId: '@workflow().run.correlationId'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
            }
          }
          runAfter: {
            'Determine_scaling_action': ['Succeeded']
          }
        }
        'Response': {
          type: 'Response'
          inputs: {
            statusCode: 200
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              message: 'Scaling operation completed successfully'
              alertType: '@triggerBody()[\'alertType\']'
              timestamp: '@utcNow()'
              workflowRunId: '@workflow().run.name'
            }
          }
          runAfter: {
            'Log_scaling_operation': ['Succeeded']
          }
        }
      }
    }
  }
}

// ==============================================================================
// RBAC ROLE ASSIGNMENTS
// ==============================================================================

// Grant Logic App SQL DB Contributor role
resource logicAppSqlContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, logicApp.id, 'SQL DB Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec') // SQL DB Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Logic App Key Vault Secrets User role
resource logicAppKeyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, logicApp.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Logic App Log Analytics Contributor role
resource logicAppLogAnalyticsContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspace.id, logicApp.id, 'Log Analytics Contributor')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293') // Log Analytics Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==============================================================================
// MONITORING AND ALERTING
// ==============================================================================

// Action group for scaling alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'ScaleAlert'
    enabled: true
    webhookReceivers: [
      {
        name: 'LogicAppScalingWebhook'
        serviceUri: listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicApp.name, 'When_HTTP_request_received'), '2019-05-01').value
        useCommonAlertSchema: true
      }
    ]
  }
}

// CPU Scale Up Alert
resource cpuScaleUpAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertNames.cpuScaleUp
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when CPU utilization exceeds scale-up threshold'
    severity: 2
    enabled: true
    scopes: [
      sqlDatabase.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT${scaleUpWindowMinutes}M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CPU_Utilization'
          metricName: 'cpu_percent'
          metricNamespace: 'Microsoft.Sql/servers/databases'
          operator: 'GreaterThan'
          threshold: scaleUpCpuThreshold
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {
          alertType: 'CPU-Scale-Up-Alert'
        }
      }
    ]
  }
}

// CPU Scale Down Alert
resource cpuScaleDownAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertNames.cpuScaleDown
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when CPU utilization falls below scale-down threshold'
    severity: 3
    enabled: true
    scopes: [
      sqlDatabase.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT${scaleDownWindowMinutes}M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CPU_Utilization'
          metricName: 'cpu_percent'
          metricNamespace: 'Microsoft.Sql/servers/databases'
          operator: 'LessThan'
          threshold: scaleDownCpuThreshold
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {
          alertType: 'CPU-Scale-Down-Alert'
        }
      }
    ]
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('SQL Server name')
output sqlServerName string = sqlServer.name

@description('SQL Database name')
output sqlDatabaseName string = sqlDatabase.name

@description('SQL Server FQDN')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('SQL Database connection string (without credentials)')
output sqlDatabaseConnectionStringTemplate string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabase.name};Persist Security Info=False;User ID={username};Password={password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

@description('Logic App name')
output logicAppName string = logicApp.name

@description('Logic App resource ID')
output logicAppResourceId string = logicApp.id

@description('Logic App trigger URL')
output logicAppTriggerUrl string = listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicApp.name, 'When_HTTP_request_received'), '2019-05-01').value

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Action group name')
output actionGroupName string = actionGroup.name

@description('CPU Scale Up Alert name')
output cpuScaleUpAlertName string = cpuScaleUpAlert.name

@description('CPU Scale Down Alert name')
output cpuScaleDownAlertName string = cpuScaleDownAlert.name

@description('Current database capacity (vCores)')
output currentDatabaseCapacity int = sqlDatabase.sku.capacity

@description('Scaling configuration summary')
output scalingConfiguration object = {
  initialCapacity: initialDatabaseCapacity
  minCapacity: minDatabaseCapacity
  maxCapacity: maxDatabaseCapacity
  scaleUpThreshold: scaleUpCpuThreshold
  scaleDownThreshold: scaleDownCpuThreshold
  scaleUpWindowMinutes: scaleUpWindowMinutes
  scaleDownWindowMinutes: scaleDownWindowMinutes
}

@description('Resource tags applied to all resources')
output resourceTags object = tags