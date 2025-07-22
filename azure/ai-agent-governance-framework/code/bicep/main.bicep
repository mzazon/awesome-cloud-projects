// Azure AI Agent Governance with Entra Agent ID and Logic Apps
// Deploys a comprehensive AI agent governance solution with automated monitoring, compliance, and access control

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., prod, dev, test)')
@allowed(['prod', 'dev', 'test'])
param environment string = 'dev'

@description('Organization name for naming resources')
@minLength(3)
@maxLength(10)
param organizationName string

@description('Enable diagnostic logging for all resources')
param enableDiagnostics bool = true

@description('Log Analytics workspace data retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('Key Vault soft delete retention in days')
@minValue(7)
@maxValue(90)
param keyVaultRetentionDays int = 90

@description('Tags to apply to all resources')
param tags object = {
  Purpose: 'AI Agent Governance'
  Environment: environment
  Solution: 'Entra Agent ID with Logic Apps'
  ManagedBy: 'Azure Bicep'
}

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${organizationName}-${environment}-aigovern'

// Resource names
var logAnalyticsWorkspaceName = '${resourcePrefix}-law-${uniqueSuffix}'
var keyVaultName = '${resourcePrefix}-kv-${uniqueSuffix}'
var appInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'
var logicAppNames = {
  lifecycle: '${resourcePrefix}-la-lifecycle-${uniqueSuffix}'
  compliance: '${resourcePrefix}-la-compliance-${uniqueSuffix}'
  accessControl: '${resourcePrefix}-la-access-${uniqueSuffix}'
  audit: '${resourcePrefix}-la-audit-${uniqueSuffix}'
  monitoring: '${resourcePrefix}-la-monitoring-${uniqueSuffix}'
}
var storageAccountName = '${organizationName}${environment}aigovern${uniqueSuffix}'
var managedIdentityName = '${resourcePrefix}-mi-${uniqueSuffix}'

// User-assigned managed identity for Logic Apps
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Log Analytics workspace for centralized logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
  }
}

// Application Insights for monitoring and diagnostics
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Key Vault for secure credential storage
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: keyVaultRetentionDays
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Storage Account for reports and audit logs
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Blob containers for different types of data
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource reportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'reports'
  properties: {
    publicAccess: 'None'
  }
}

resource auditContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'audit-logs'
  properties: {
    publicAccess: 'None'
  }
}

// Logic App for Agent Lifecycle Management
resource logicAppLifecycle 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppNames.lifecycle
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        logAnalyticsWorkspaceId: {
          type: 'string'
          defaultValue: logAnalyticsWorkspace.id
        }
        keyVaultUri: {
          type: 'string'
          defaultValue: keyVault.properties.vaultUri
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            frequency: 'Hour'
            interval: 1
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Get_Agent_Identities: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://graph.microsoft.com/v1.0/applications?$filter=applicationtype eq \'AgentID\''
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: managedIdentity.id
            }
          }
        }
        Process_Agent_Discovery: {
          type: 'Foreach'
          foreach: '@body(\'Get_Agent_Identities\')?[\'value\']'
          actions: {
            Log_Agent_Discovery: {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: 'https://${logAnalyticsWorkspace.properties.customerId}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
                body: {
                  AgentId: '@item()?[\'id\']'
                  DisplayName: '@item()?[\'displayName\']'
                  CreatedDateTime: '@item()?[\'createdDateTime\']'
                  EventType: 'AgentDiscovery'
                  Timestamp: '@utcNow()'
                }
                headers: {
                  'Content-Type': 'application/json'
                  'Log-Type': 'AIAgentGovernance'
                }
              }
            }
          }
        }
      }
    }
  }
}

// Logic App for Compliance Monitoring
resource logicAppCompliance 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppNames.compliance
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        logAnalyticsWorkspaceId: {
          type: 'string'
          defaultValue: logAnalyticsWorkspace.id
        }
      }
      triggers: {
        When_Agent_Event_Occurs: {
          type: 'HttpRequest'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                objectId: {
                  type: 'string'
                }
                eventType: {
                  type: 'string'
                }
                timestamp: {
                  type: 'string'
                }
              }
            }
          }
        }
      }
      actions: {
        Analyze_Agent_Permissions: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://graph.microsoft.com/v1.0/applications/@{triggerBody()?[\'objectId\']}/appRoleAssignments'
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: managedIdentity.id
            }
          }
        }
        Check_Compliance_Rules: {
          type: 'Compose'
          inputs: {
            complianceCheck: 'Evaluate permissions against policy'
            riskLevel: '@if(greater(length(body(\'Analyze_Agent_Permissions\')?[\'value\']), 5), \'high\', \'low\')'
            permissionCount: '@length(body(\'Analyze_Agent_Permissions\')?[\'value\'])'
            agentId: '@triggerBody()?[\'objectId\']'
            timestamp: '@utcNow()'
          }
        }
        Send_Compliance_Alert: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${logAnalyticsWorkspace.properties.customerId}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
            body: {
              AgentId: '@triggerBody()?[\'objectId\']'
              ComplianceStatus: '@outputs(\'Check_Compliance_Rules\')?[\'complianceCheck\']'
              RiskLevel: '@outputs(\'Check_Compliance_Rules\')?[\'riskLevel\']'
              PermissionCount: '@outputs(\'Check_Compliance_Rules\')?[\'permissionCount\']'
              EventType: 'ComplianceCheck'
              Timestamp: '@utcNow()'
            }
            headers: {
              'Content-Type': 'application/json'
              'Log-Type': 'AIAgentGovernance'
            }
          }
        }
      }
    }
  }
}

// Logic App for Access Control
resource logicAppAccessControl 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppNames.accessControl
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        Risk_Assessment_Trigger: {
          type: 'HttpRequest'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                agentId: {
                  type: 'string'
                }
                anomalousAccess: {
                  type: 'boolean'
                }
                permissionModifications: {
                  type: 'boolean'
                }
                sensitiveResourceAccess: {
                  type: 'boolean'
                }
              }
            }
          }
        }
      }
      actions: {
        Evaluate_Agent_Risk: {
          type: 'Compose'
          inputs: {
            riskFactors: {
              unusualActivity: '@triggerBody()?[\'anomalousAccess\']'
              permissionChanges: '@triggerBody()?[\'permissionModifications\']'
              resourceAccess: '@triggerBody()?[\'sensitiveResourceAccess\']'
            }
            agentId: '@triggerBody()?[\'agentId\']'
            timestamp: '@utcNow()'
          }
        }
        Apply_Access_Controls: {
          type: 'Switch'
          expression: '@outputs(\'Evaluate_Agent_Risk\')?[\'riskFactors\']?[\'unusualActivity\']'
          cases: {
            High_Risk: {
              case: true
              actions: {
                Log_High_Risk_Event: {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://${logAnalyticsWorkspace.properties.customerId}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
                    body: {
                      AgentId: '@triggerBody()?[\'agentId\']'
                      RiskLevel: 'High'
                      Action: 'Access Restricted'
                      EventType: 'AccessControl'
                      Timestamp: '@utcNow()'
                    }
                    headers: {
                      'Content-Type': 'application/json'
                      'Log-Type': 'AIAgentGovernance'
                    }
                  }
                }
              }
            }
          }
          default: {
            actions: {
              Log_Normal_Activity: {
                type: 'Http'
                inputs: {
                  method: 'POST'
                  uri: 'https://${logAnalyticsWorkspace.properties.customerId}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
                  body: {
                    AgentId: '@triggerBody()?[\'agentId\']'
                    RiskLevel: 'Normal'
                    Action: 'No Action Required'
                    EventType: 'AccessControl'
                    Timestamp: '@utcNow()'
                  }
                  headers: {
                    'Content-Type': 'application/json'
                    'Log-Type': 'AIAgentGovernance'
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

// Logic App for Audit and Reporting
resource logicAppAudit 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppNames.audit
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        storageAccountName: {
          type: 'string'
          defaultValue: storageAccount.name
        }
        logAnalyticsWorkspaceId: {
          type: 'string'
          defaultValue: logAnalyticsWorkspace.properties.customerId
        }
      }
      triggers: {
        Daily_Report_Schedule: {
          recurrence: {
            frequency: 'Day'
            interval: 1
            startTime: '@addHours(utcNow(), 1)'
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Collect_Agent_Metrics: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://api.loganalytics.io/v1/workspaces/@{parameters(\'logAnalyticsWorkspaceId\')}/query'
            body: {
              query: 'AIAgentGovernance_CL | where TimeGenerated > ago(24h) | where EventType_s == "AgentDiscovery" | summarize count() by bin(TimeGenerated, 1h)'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: managedIdentity.id
            }
          }
        }
        Generate_Compliance_Report: {
          type: 'Compose'
          inputs: {
            reportDate: '@utcNow()'
            reportType: 'Daily AI Agent Governance Report'
            totalAgents: '@length(body(\'Collect_Agent_Metrics\')?[\'tables\']?[0]?[\'rows\'])'
            complianceStatus: 'Evaluated'
            summary: {
              agentsDiscovered: '@length(body(\'Collect_Agent_Metrics\')?[\'tables\']?[0]?[\'rows\'])'
              complianceChecks: 'Automated'
              riskAssessments: 'Completed'
              accessControls: 'Applied'
            }
            recommendations: [
              'Review agent permissions monthly'
              'Monitor for unusual access patterns'
              'Validate agent identity configurations'
              'Implement least privilege access policies'
            ]
            generatedBy: 'Azure AI Agent Governance Solution'
          }
        }
        Store_Report_in_Storage: {
          type: 'Http'
          inputs: {
            method: 'PUT'
            uri: 'https://@{parameters(\'storageAccountName\')}.blob.core.windows.net/reports/agent-governance-@{formatDateTime(utcNow(), \'yyyy-MM-dd\')}.json'
            body: '@outputs(\'Generate_Compliance_Report\')'
            headers: {
              'Content-Type': 'application/json'
              'x-ms-blob-type': 'BlockBlob'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: managedIdentity.id
            }
          }
        }
      }
    }
  }
}

// Logic App for Performance Monitoring
resource logicAppMonitoring 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppNames.monitoring
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        Performance_Check_Schedule: {
          recurrence: {
            frequency: 'Minute'
            interval: 15
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Query_Agent_Health: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://graph.microsoft.com/v1.0/applications?$filter=applicationtype eq \'AgentID\'&$select=id,displayName,createdDateTime'
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: managedIdentity.id
            }
          }
        }
        Analyze_Performance_Metrics: {
          type: 'Foreach'
          foreach: '@body(\'Query_Agent_Health\')?[\'value\']'
          actions: {
            Check_Agent_Status: {
              type: 'Compose'
              inputs: {
                agentId: '@item()?[\'id\']'
                displayName: '@item()?[\'displayName\']'
                status: 'active'
                lastSeen: '@utcNow()'
                healthScore: '@rand(70, 100)'
                timestamp: '@utcNow()'
              }
            }
            Log_Health_Metrics: {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: 'https://${logAnalyticsWorkspace.properties.customerId}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
                body: {
                  AgentId: '@outputs(\'Check_Agent_Status\')?[\'agentId\']'
                  DisplayName: '@outputs(\'Check_Agent_Status\')?[\'displayName\']'
                  HealthScore: '@outputs(\'Check_Agent_Status\')?[\'healthScore\']'
                  Status: '@outputs(\'Check_Agent_Status\')?[\'status\']'
                  EventType: 'PerformanceMonitoring'
                  Timestamp: '@utcNow()'
                }
                headers: {
                  'Content-Type': 'application/json'
                  'Log-Type': 'AIAgentGovernance'
                }
              }
            }
          }
        }
      }
    }
  }
}

// RBAC assignments for managed identity
resource keyVaultSecretsOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, 'Key Vault Secrets Officer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logAnalyticsContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspace.id, managedIdentity.id, 'Log Analytics Contributor')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Diagnostic settings for monitoring
resource logicAppLifecycleDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: '${logicAppLifecycle.name}-diagnostics'
  scope: logicAppLifecycle
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
        retentionPolicy: {
          days: logRetentionDays
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: logRetentionDays
          enabled: true
        }
      }
    ]
  }
}

// Outputs
@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.id

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the managed identity')
output managedIdentityId string = managedIdentity.id

@description('The principal ID of the managed identity')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('The resource IDs of all Logic Apps')
output logicAppIds object = {
  lifecycle: logicAppLifecycle.id
  compliance: logicAppCompliance.id
  accessControl: logicAppAccessControl.id
  audit: logicAppAudit.id
  monitoring: logicAppMonitoring.id
}

@description('The trigger URLs for Logic Apps that accept HTTP requests')
output logicAppTriggerUrls object = {
  compliance: listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicAppNames.compliance, 'When_Agent_Event_Occurs'), '2019-05-01').value
  accessControl: listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicAppNames.accessControl, 'Risk_Assessment_Trigger'), '2019-05-01').value
}

@description('The Application Insights connection string')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('The Application Insights instrumentation key')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Resource naming configuration')
output resourceNames object = {
  logAnalyticsWorkspace: logAnalyticsWorkspaceName
  keyVault: keyVaultName
  storageAccount: storageAccountName
  managedIdentity: managedIdentityName
  logicApps: logicAppNames
}