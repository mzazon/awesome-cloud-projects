// ==============================================================================
// Main Bicep template for Intelligent Code Quality Pipeline
// This template orchestrates Azure resources for code quality automation
// ==============================================================================

@description('The location where resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Application Insights configuration')
param appInsights object = {
  name: 'ai-quality-${uniqueSuffix}'
  kind: 'web'
  applicationType: 'web'
  retentionInDays: 90
  samplingPercentage: 100
}

@description('Logic Apps configuration')
param logicApps object = {
  name: 'la-quality-feedback-${uniqueSuffix}'
  qualityThreshold: 80
  enableDiagnostics: true
}

@description('Storage account configuration for Logic Apps')
param storageAccount object = {
  name: 'stquality${uniqueSuffix}'
  sku: 'Standard_LRS'
  kind: 'StorageV2'
  accessTier: 'Hot'
  enableBlobEncryption: true
  enableFileEncryption: true
}

@description('Log Analytics workspace configuration')
param logAnalytics object = {
  name: 'law-quality-${uniqueSuffix}'
  sku: 'PerGB2018'
  retentionInDays: 30
}

@description('Key Vault configuration for storing secrets')
param keyVault object = {
  name: 'kv-quality-${uniqueSuffix}'
  sku: 'standard'
  enabledForDeployment: false
  enabledForDiskEncryption: false
  enabledForTemplateDeployment: true
  enableSoftDelete: true
  softDeleteRetentionInDays: 7
}

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'CodeQualityPipeline'
  ManagedBy: 'Bicep'
  Recipe: 'IntelligentCodeQuality'
}

// ==============================================================================
// VARIABLES
// ==============================================================================

var storageAccountName = length(storageAccount.name) > 24 ? substring(storageAccount.name, 0, 24) : storageAccount.name

// ==============================================================================
// EXISTING RESOURCES
// ==============================================================================

// Get current user for Key Vault access policy
resource currentUser 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: '00000000-0000-0000-0000-000000000000' // Owner role
}

// ==============================================================================
// LOG ANALYTICS WORKSPACE
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalytics.name
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalytics.sku
    }
    retentionInDays: logAnalytics.retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ==============================================================================
// KEY VAULT
// ==============================================================================

resource keyVaultResource 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVault.name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: keyVault.sku
    }
    tenantId: subscription().tenantId
    enabledForDeployment: keyVault.enabledForDeployment
    enabledForDiskEncryption: keyVault.enabledForDiskEncryption
    enabledForTemplateDeployment: keyVault.enabledForTemplateDeployment
    enableSoftDelete: keyVault.enableSoftDelete
    softDeleteRetentionInDays: keyVault.softDeleteRetentionInDays
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    accessPolicies: []
  }
}

// ==============================================================================
// STORAGE ACCOUNT
// ==============================================================================

resource storageAccountResource 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccount.sku
  }
  kind: storageAccount.kind
  properties: {
    accessTier: storageAccount.accessTier
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    encryption: {
      services: {
        blob: {
          enabled: storageAccount.enableBlobEncryption
        }
        file: {
          enabled: storageAccount.enableFileEncryption
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// ==============================================================================
// APPLICATION INSIGHTS
// ==============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsights.name
  location: location
  tags: tags
  kind: appInsights.kind
  properties: {
    Application_Type: appInsights.applicationType
    WorkspaceResourceId: logAnalyticsWorkspace.id
    RetentionInDays: appInsights.retentionInDays
    SamplingPercentage: appInsights.samplingPercentage
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ==============================================================================
// LOGIC APPS
// ==============================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicApps.name
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        qualityThreshold: {
          type: 'int'
          defaultValue: logicApps.qualityThreshold
        }
        appInsightsInstrumentationKey: {
          type: 'string'
          defaultValue: applicationInsights.properties.InstrumentationKey
        }
      }
      triggers: {
        'quality-assessment-trigger': {
          type: 'Request'
          kind: 'Http'
          inputs: {
            method: 'POST'
            schema: {
              type: 'object'
              properties: {
                qualityScore: {
                  type: 'number'
                }
                testResults: {
                  type: 'string'
                }
                performanceMetrics: {
                  type: 'object'
                  properties: {
                    buildTime: {
                      type: 'string'
                    }
                    testCoverage: {
                      type: 'number'
                    }
                    codeComplexity: {
                      type: 'number'
                    }
                  }
                }
                repository: {
                  type: 'string'
                }
                pullRequestId: {
                  type: 'string'
                }
                buildId: {
                  type: 'string'
                }
              }
              required: ['qualityScore', 'testResults']
            }
          }
        }
      }
      actions: {
        'Parse-Quality-Data': {
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()'
            schema: {
              type: 'object'
              properties: {
                qualityScore: {
                  type: 'number'
                }
                testResults: {
                  type: 'string'
                }
                performanceMetrics: {
                  type: 'object'
                }
                repository: {
                  type: 'string'
                }
                pullRequestId: {
                  type: 'string'
                }
                buildId: {
                  type: 'string'
                }
              }
            }
          }
          runAfter: {}
        }
        'Log-Quality-Metrics': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://dc.services.visualstudio.com/v2/track'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              name: 'Microsoft.ApplicationInsights.Event'
              time: '@utcNow()'
              iKey: '@parameters(\'appInsightsInstrumentationKey\')'
              data: {
                baseType: 'EventData'
                baseData: {
                  name: 'CodeQualityAssessment'
                  properties: {
                    qualityScore: '@body(\'Parse-Quality-Data\')?[\'qualityScore\']'
                    testResults: '@body(\'Parse-Quality-Data\')?[\'testResults\']'
                    repository: '@body(\'Parse-Quality-Data\')?[\'repository\']'
                    pullRequestId: '@body(\'Parse-Quality-Data\')?[\'pullRequestId\']'
                    buildId: '@body(\'Parse-Quality-Data\')?[\'buildId\']'
                  }
                  measurements: {
                    qualityScore: '@body(\'Parse-Quality-Data\')?[\'qualityScore\']'
                    testCoverage: '@body(\'Parse-Quality-Data\')?[\'performanceMetrics\']?[\'testCoverage\']'
                    codeComplexity: '@body(\'Parse-Quality-Data\')?[\'performanceMetrics\']?[\'codeComplexity\']'
                  }
                }
              }
            }
          }
          runAfter: {
            'Parse-Quality-Data': ['Succeeded']
          }
        }
        'Evaluate-Quality-Gate': {
          type: 'If'
          expression: {
            and: [
              {
                greater: [
                  '@body(\'Parse-Quality-Data\')?[\'qualityScore\']'
                  '@parameters(\'qualityThreshold\')'
                ]
              }
              {
                equals: [
                  '@body(\'Parse-Quality-Data\')?[\'testResults\']'
                  'success'
                ]
              }
            ]
          }
          actions: {
            'Quality-Gate-Passed': {
              type: 'Response'
              inputs: {
                statusCode: 200
                headers: {
                  'Content-Type': 'application/json'
                }
                body: {
                  status: 'success'
                  message: 'Quality gate passed - deployment approved'
                  qualityScore: '@body(\'Parse-Quality-Data\')?[\'qualityScore\']'
                  threshold: '@parameters(\'qualityThreshold\')'
                  timestamp: '@utcNow()'
                  recommendations: [
                    'Continue with deployment pipeline'
                    'Monitor post-deployment metrics'
                  ]
                }
              }
            }
            'Trigger-Deployment-Notification': {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: 'https://dev.azure.com/webhook/deployment-approved'
                headers: {
                  'Content-Type': 'application/json'
                }
                body: {
                  buildId: '@body(\'Parse-Quality-Data\')?[\'buildId\']'
                  pullRequestId: '@body(\'Parse-Quality-Data\')?[\'pullRequestId\']'
                  status: 'approved'
                  qualityScore: '@body(\'Parse-Quality-Data\')?[\'qualityScore\']'
                }
              }
              runAfter: {
                'Quality-Gate-Passed': ['Succeeded']
              }
            }
          }
          else: {
            actions: {
              'Quality-Gate-Failed': {
                type: 'Response'
                inputs: {
                  statusCode: 400
                  headers: {
                    'Content-Type': 'application/json'
                  }
                  body: {
                    status: 'failure'
                    message: 'Quality gate failed - deployment blocked'
                    qualityScore: '@body(\'Parse-Quality-Data\')?[\'qualityScore\']'
                    threshold: '@parameters(\'qualityThreshold\')'
                    timestamp: '@utcNow()'
                    recommendations: [
                      'Review code quality issues'
                      'Increase test coverage'
                      'Address static analysis findings'
                      'Rerun quality checks after fixes'
                    ]
                  }
                }
              }
              'Create-Quality-Issue': {
                type: 'Http'
                inputs: {
                  method: 'POST'
                  uri: 'https://dev.azure.com/api/workitems'
                  headers: {
                    'Content-Type': 'application/json'
                  }
                  body: {
                    title: 'Quality Gate Failure - Build @{body(\'Parse-Quality-Data\')?[\'buildId\']}'
                    description: 'Quality score @{body(\'Parse-Quality-Data\')?[\'qualityScore\']} below threshold @{parameters(\'qualityThreshold\')}'
                    priority: 'High'
                    type: 'Bug'
                  }
                }
                runAfter: {
                  'Quality-Gate-Failed': ['Succeeded']
                }
              }
            }
          }
          runAfter: {
            'Log-Quality-Metrics': ['Succeeded']
          }
        }
      }
    }
  }
}

// ==============================================================================
// DIAGNOSTIC SETTINGS
// ==============================================================================

resource logicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logicApps.enableDiagnostics) {
  name: 'logicapp-diagnostics'
  scope: logicApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
  }
}

resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'storage-diagnostics'
  scope: storageAccountResource
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
  }
}

// ==============================================================================
// RBAC ASSIGNMENTS
// ==============================================================================

// Key Vault Secrets User role for Logic Apps
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

resource logicAppKeyVaultAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVaultResource
  name: guid(keyVaultResource.id, logicApp.id, keyVaultSecretsUserRole.id)
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Application Insights instrumentation key')
output appInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output appInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Application Insights resource ID')
output appInsightsResourceId string = applicationInsights.id

@description('Logic App webhook URL for quality gate integration')
output logicAppWebhookUrl string = logicApp.properties.accessEndpoint

@description('Logic App resource ID')
output logicAppResourceId string = logicApp.id

@description('Logic App principal ID for RBAC assignments')
output logicAppPrincipalId string = logicApp.identity.principalId

@description('Storage account name')
output storageAccountName string = storageAccountResource.name

@description('Storage account connection string')
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountResource.name};AccountKey=${storageAccountResource.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Key Vault URI')
output keyVaultUri string = keyVaultResource.properties.vaultUri

@description('Key Vault resource ID')
output keyVaultResourceId string = keyVaultResource.id

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics workspace resource ID')
output logAnalyticsResourceId string = logAnalyticsWorkspace.id

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  uniqueSuffix: uniqueSuffix
  resources: {
    applicationInsights: applicationInsights.name
    logicApp: logicApp.name
    storageAccount: storageAccountResource.name
    keyVault: keyVaultResource.name
    logAnalyticsWorkspace: logAnalyticsWorkspace.name
  }
  endpoints: {
    logicAppWebhook: logicApp.properties.accessEndpoint
    keyVaultUri: keyVaultResource.properties.vaultUri
  }
  configuration: {
    qualityThreshold: logicApps.qualityThreshold
    retentionDays: appInsights.retentionInDays
    environment: environment
  }
}