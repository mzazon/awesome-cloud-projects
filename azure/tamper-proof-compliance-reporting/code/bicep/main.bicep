// Azure Confidential Ledger and Logic Apps Compliance Reporting Solution
// This template deploys a complete automated compliance reporting infrastructure
// with tamper-proof audit trails and automated workflow orchestration

targetScope = 'resourceGroup'

// ================================================================================
// PARAMETERS
// ================================================================================

@description('The name prefix for all resources')
param namePrefix string = 'compliance'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  project: 'compliance-reporting'
  environment: environment
  deployedBy: 'bicep'
  lastUpdated: utcNow('yyyy-MM-dd')
}

@description('The Azure AD tenant ID for authentication')
param tenantId string = tenant().tenantId

@description('Enable confidential ledger high availability')
param enableHighAvailability bool = false

@description('The SKU for Log Analytics workspace')
@allowed(['PerGB2018', 'PerNode', 'Premium', 'Standard', 'Standalone', 'Unlimited', 'CapacityReservation'])
param logAnalyticsSkuName string = 'PerGB2018'

@description('Data retention period for Log Analytics in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 90

@description('Storage account SKU for compliance reports')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS', 'Premium_LRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Enable blob versioning for audit trails')
param enableBlobVersioning bool = true

@description('Logic Apps workflow frequency for compliance checks')
@allowed(['Day', 'Hour', 'Minute', 'Month', 'Week'])
param workflowFrequency string = 'Hour'

@description('Logic Apps workflow interval')
@minValue(1)
@maxValue(1000)
param workflowInterval int = 6

@description('Email address for compliance notifications')
param notificationEmail string = ''

@description('Enable advanced threat protection for storage')
param enableAdvancedThreatProtection bool = true

// ================================================================================
// VARIABLES
// ================================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var confidentialLedgerName = '${namePrefix}-acl-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${namePrefix}-law-${uniqueSuffix}'
var storageAccountName = '${namePrefix}st${uniqueSuffix}'
var logicAppName = '${namePrefix}-la-${uniqueSuffix}'
var actionGroupName = '${namePrefix}-ag-${uniqueSuffix}'
var keyVaultName = '${namePrefix}-kv-${uniqueSuffix}'
var applicationInsightsName = '${namePrefix}-ai-${uniqueSuffix}'

// Resource names with environment suffix
var resourceNames = {
  confidentialLedger: '${confidentialLedgerName}-${environment}'
  logAnalyticsWorkspace: '${logAnalyticsWorkspaceName}-${environment}'
  storageAccount: '${storageAccountName}${environment}'
  logicApp: '${logicAppName}-${environment}'
  actionGroup: '${actionGroupName}-${environment}'
  keyVault: '${keyVaultName}-${environment}'
  applicationInsights: '${applicationInsightsName}-${environment}'
}

// Common metadata for all resources
var commonTags = union(tags, {
  resourceGroup: resourceGroup().name
  location: location
  confidentialLedgerName: resourceNames.confidentialLedger
})

// Storage containers for compliance data
var storageContainers = [
  {
    name: 'compliance-reports'
    publicAccess: 'None'
  }
  {
    name: 'audit-logs'
    publicAccess: 'None'
  }
  {
    name: 'evidence-vault'
    publicAccess: 'None'
  }
]

// ================================================================================
// LOG ANALYTICS WORKSPACE
// ================================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: logAnalyticsSkuName
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ================================================================================
// APPLICATION INSIGHTS
// ================================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ================================================================================
// KEY VAULT FOR SECRETS MANAGEMENT
// ================================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: commonTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// ================================================================================
// STORAGE ACCOUNT FOR COMPLIANCE REPORTS
// ================================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: commonTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: true
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// Blob service configuration
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: true
      retentionInDays: 30
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    isVersioningEnabled: enableBlobVersioning
  }
}

// Storage containers for compliance data
resource storageContainerLoop 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for container in storageContainers: {
  parent: blobService
  name: container.name
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: container.publicAccess
  }
}]

// Advanced threat protection for storage
resource storageAdvancedThreatProtection 'Microsoft.Security/advancedThreatProtectionSettings@2019-01-01' = if (enableAdvancedThreatProtection) {
  scope: storageAccount
  name: 'current'
  properties: {
    isEnabled: true
  }
}

// ================================================================================
// LOGIC APP MANAGED IDENTITY
// ================================================================================

resource logicAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${resourceNames.logicApp}-identity'
  location: location
  tags: commonTags
}

// ================================================================================
// AZURE CONFIDENTIAL LEDGER
// ================================================================================

resource confidentialLedger 'Microsoft.ConfidentialLedger/ledgers@2023-01-26' = {
  name: resourceNames.confidentialLedger
  location: location
  tags: commonTags
  properties: {
    ledgerType: 'Private'
    aadBasedSecurityPrincipals: [
      {
        principalId: logicAppIdentity.properties.principalId
        ledgerRoleName: 'Contributor'
      }
    ]
    certBasedSecurityPrincipals: []
    runningState: 'Active'
  }
}

// ================================================================================
// ACTION GROUP FOR NOTIFICATIONS
// ================================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'Global'
  tags: commonTags
  properties: {
    groupShortName: 'compliance'
    enabled: true
    emailReceivers: empty(notificationEmail) ? [] : [
      {
        name: 'ComplianceTeam'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureFunctionReceivers: []
    logicAppReceivers: []
  }
}

// ================================================================================
// LOGIC APP WITH MANAGED IDENTITY
// ================================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: resourceNames.logicApp
  location: location
  tags: commonTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${logicAppIdentity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        ledgerEndpoint: {
          defaultValue: confidentialLedger.properties.ledgerUri
          type: 'String'
        }
        storageAccountName: {
          defaultValue: storageAccount.name
          type: 'String'
        }
        containerName: {
          defaultValue: 'compliance-reports'
          type: 'String'
        }
      }
      triggers: {
        'Compliance_Check_Schedule': {
          recurrence: {
            frequency: workflowFrequency
            interval: workflowInterval
            timeZone: 'UTC'
          }
          type: 'Recurrence'
        }
        'Manual_Trigger': {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                eventType: {
                  type: 'string'
                }
                severity: {
                  type: 'string'
                }
                description: {
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
        'Initialize_Variables': {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'ComplianceEvent'
                type: 'Object'
                value: {
                  eventId: '@{guid()}'
                  timestamp: '@{utcNow()}'
                  source: 'ComplianceMonitoring'
                  eventType: '@{coalesce(triggerBody()?[\'eventType\'], \'ScheduledCheck\')}'
                  severity: '@{coalesce(triggerBody()?[\'severity\'], \'Information\')}'
                  description: '@{coalesce(triggerBody()?[\'description\'], \'Automated compliance verification\')}'
                }
              }
            ]
          }
        }
        'Record_to_Confidential_Ledger': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@{parameters(\'ledgerEndpoint\')}/app/transactions'
            headers: {
              'Content-Type': 'application/json'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: logicAppIdentity.id
            }
            body: {
              contents: '@variables(\'ComplianceEvent\')'
            }
          }
          runAfter: {
            'Initialize_Variables': ['Succeeded']
          }
        }
        'Generate_Compliance_Report': {
          type: 'Compose'
          inputs: {
            reportId: '@{guid()}'
            generatedAt: '@{utcNow()}'
            complianceStatus: 'Verified'
            eventDetails: '@variables(\'ComplianceEvent\')'
            ledgerTransaction: '@body(\'Record_to_Confidential_Ledger\')'
            verificationDetails: {
              immutableRecord: true
              cryptographicProof: '@body(\'Record_to_Confidential_Ledger\')?[\'transactionId\']'
              auditTrail: 'Recorded in Azure Confidential Ledger with TEE protection'
            }
          }
          runAfter: {
            'Record_to_Confidential_Ledger': ['Succeeded']
          }
        }
        'Save_Report_to_Blob_Storage': {
          type: 'Http'
          inputs: {
            method: 'PUT'
            uri: 'https://@{parameters(\'storageAccountName\')}.blob.core.windows.net/@{parameters(\'containerName\')}/compliance-report-@{utcNow(\'yyyy-MM-dd-HH-mm-ss\')}.json'
            headers: {
              'Content-Type': 'application/json'
              'x-ms-blob-type': 'BlockBlob'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: logicAppIdentity.id
            }
            body: '@outputs(\'Generate_Compliance_Report\')'
          }
          runAfter: {
            'Generate_Compliance_Report': ['Succeeded']
          }
        }
        'Log_to_Analytics': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://@{split(split(reference(resourceId(\'Microsoft.OperationalInsights/workspaces\', \'${resourceNames.logAnalyticsWorkspace}\')).customerId, \'.\')[0], \'-\')[0]}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
            headers: {
              'Content-Type': 'application/json'
              'Log-Type': 'ComplianceEvents'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: logicAppIdentity.id
            }
            body: [
              '@variables(\'ComplianceEvent\')'
            ]
          }
          runAfter: {
            'Save_Report_to_Blob_Storage': ['Succeeded']
          }
        }
      }
      outputs: {
        ComplianceReportGenerated: {
          type: 'Object'
          value: '@outputs(\'Generate_Compliance_Report\')'
        }
      }
    }
    parameters: {}
  }
}

// ================================================================================
// RBAC ROLE ASSIGNMENTS
// ================================================================================

// Grant Logic App access to Confidential Ledger
resource confidentialLedgerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(confidentialLedger.id, logicAppIdentity.id, 'ConfidentialLedgerContributor')
  scope: confidentialLedger
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '6e86ad56-9a8f-45f1-94e7-d7082e0406e8') // Confidential Ledger Contributor
    principalId: logicAppIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Allows Logic App to read and write to Confidential Ledger for compliance recording'
  }
}

// Grant Logic App access to Storage Account
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, logicAppIdentity.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: logicAppIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Allows Logic App to read and write compliance reports to blob storage'
  }
}

// Grant Logic App access to Log Analytics
resource logAnalyticsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspace.id, logicAppIdentity.id, 'LogAnalyticsContributor')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293') // Log Analytics Contributor
    principalId: logicAppIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Allows Logic App to write compliance events to Log Analytics'
  }
}

// Grant Logic App access to Key Vault
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, logicAppIdentity.id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: logicAppIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Allows Logic App to read secrets from Key Vault'
  }
}

// ================================================================================
// ALERT RULES FOR COMPLIANCE MONITORING
// ================================================================================

// Alert rule for high-severity compliance violations
resource highSeverityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${namePrefix}-high-severity-compliance-alert'
  location: 'Global'
  tags: commonTags
  properties: {
    description: 'Alert triggered when high-severity compliance violations are detected'
    severity: 1
    enabled: true
    scopes: [
      logAnalyticsWorkspace.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 1
          name: 'HighSeverityViolations'
          metricNamespace: 'Microsoft.OperationalInsights/workspaces'
          metricName: 'Heartbeat'
          operator: 'GreaterThan'
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// ================================================================================
// DIAGNOSTIC SETTINGS
// ================================================================================

// Diagnostic settings for Confidential Ledger
resource confidentialLedgerDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'confidential-ledger-diagnostics'
  scope: confidentialLedger
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
  }
}

// Diagnostic settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'storage-account-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
  }
}

// Diagnostic settings for Logic App
resource logicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'logic-app-diagnostics'
  scope: logicApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
  }
}

// ================================================================================
// OUTPUTS
// ================================================================================

@description('The resource ID of the Azure Confidential Ledger')
output confidentialLedgerResourceId string = confidentialLedger.id

@description('The URI of the Azure Confidential Ledger')
output confidentialLedgerUri string = confidentialLedger.properties.ledgerUri

@description('The name of the Azure Confidential Ledger')
output confidentialLedgerName string = confidentialLedger.name

@description('The resource ID of the Logic App')
output logicAppResourceId string = logicApp.id

@description('The access endpoint of the Logic App')
output logicAppAccessEndpoint string = logicApp.properties.accessEndpoint

@description('The name of the Logic App')
output logicAppName string = logicApp.name

@description('The resource ID of the storage account')
output storageAccountResourceId string = storageAccount.id

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary endpoint of the storage account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.id

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The resource ID of the Key Vault')
output keyVaultResourceId string = keyVault.id

@description('The vault URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The resource ID of Application Insights')
output applicationInsightsResourceId string = applicationInsights.id

@description('The instrumentation key of Application Insights')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The connection string of Application Insights')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The principal ID of the Logic App managed identity')
output logicAppPrincipalId string = logicAppIdentity.properties.principalId

@description('The resource ID of the Logic App managed identity')
output logicAppIdentityResourceId string = logicAppIdentity.id

@description('The resource ID of the action group')
output actionGroupResourceId string = actionGroup.id

@description('The name of the action group')
output actionGroupName string = actionGroup.name

@description('A summary of all deployed resources')
output deploymentSummary object = {
  confidentialLedger: {
    name: confidentialLedger.name
    uri: confidentialLedger.properties.ledgerUri
    type: confidentialLedger.properties.ledgerType
  }
  logicApp: {
    name: logicApp.name
    endpoint: logicApp.properties.accessEndpoint
    state: logicApp.properties.state
  }
  storageAccount: {
    name: storageAccount.name
    endpoint: storageAccount.properties.primaryEndpoints.blob
    sku: storageAccount.sku.name
  }
  monitoring: {
    logAnalyticsWorkspace: logAnalyticsWorkspace.name
    applicationInsights: applicationInsights.name
    actionGroup: actionGroup.name
  }
  security: {
    keyVault: keyVault.name
    managedIdentity: logicAppIdentity.name
  }
}