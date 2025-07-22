@description('The location for all resources')
param location string = resourceGroup().location

@description('The environment name (e.g., dev, prod)')
param environmentName string = 'dev'

@description('The project name used for resource naming')
param projectName string = 'netsec-orchestration'

@description('The unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The address prefix for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('The address prefix for the protected subnet')
param protectedSubnetAddressPrefix string = '10.0.1.0/24'

@description('The SKU for the Log Analytics workspace')
@allowed([
  'PerGB2018'
  'Free'
  'Standalone'
  'PerNode'
  'Standard'
  'Premium'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('The retention period for Log Analytics workspace in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 90

@description('The access tier for the storage account')
@allowed([
  'Hot'
  'Cool'
])
param storageAccountAccessTier string = 'Hot'

@description('The SKU for the storage account')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('The tenant ID for Key Vault access')
param tenantId string = subscription().tenantId

@description('The object ID of the user/service principal for Key Vault access')
param keyVaultAdminObjectId string

@description('Enable diagnostic settings for all resources')
param enableDiagnostics bool = true

@description('Resource tags')
param tags object = {
  Environment: environmentName
  Project: projectName
  Purpose: 'SecurityOrchestration'
  CreatedBy: 'Bicep'
}

// Variables for resource names
var resourceNames = {
  keyVault: 'kv-${projectName}-${uniqueSuffix}'
  storageAccount: 'st${replace(projectName, '-', '')}${uniqueSuffix}'
  logAnalyticsWorkspace: 'law-${projectName}-${uniqueSuffix}'
  virtualNetwork: 'vnet-${projectName}-${uniqueSuffix}'
  networkSecurityGroup: 'nsg-${projectName}-${uniqueSuffix}'
  logicApp: 'la-${projectName}-${uniqueSuffix}'
  actionGroup: 'ag-${projectName}-${uniqueSuffix}'
  applicationSecurityGroup: 'asg-${projectName}-${uniqueSuffix}'
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: logAnalyticsRetentionDays
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for Logic Apps workflow state and security events
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: storageAccountSku
  }
  properties: {
    accessTier: storageAccountAccessTier
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Storage Account Containers for security data
resource securityEventsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/security-events'
  properties: {
    publicAccess: 'None'
  }
}

resource complianceReportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/compliance-reports'
  properties: {
    publicAccess: 'None'
  }
}

// Key Vault for secure credential management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Application Security Group for micro-segmentation
resource applicationSecurityGroup 'Microsoft.Network/applicationSecurityGroups@2023-11-01' = {
  name: resourceNames.applicationSecurityGroup
  location: location
  tags: tags
  properties: {}
}

// Network Security Group with baseline security rules
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: resourceNames.networkSecurityGroup
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'Allow HTTPS traffic inbound'
        }
      }
      {
        name: 'Allow-HTTP-Inbound'
        properties: {
          priority: 1100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
          description: 'Allow HTTP traffic inbound'
        }
      }
      {
        name: 'Allow-SSH-Inbound'
        properties: {
          priority: 1200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Allow SSH traffic inbound'
        }
      }
      {
        name: 'Allow-RDP-Inbound'
        properties: {
          priority: 1300
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          description: 'Allow RDP traffic inbound'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny all other inbound traffic'
        }
      }
    ]
  }
}

// Virtual Network with protected subnet
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: resourceNames.virtualNetwork
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'protected-subnet'
        properties: {
          addressPrefix: protectedSubnetAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.KeyVault'
            }
          ]
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
    enableDdosProtection: false
  }
}

// Logic Apps Workflow for Security Orchestration
resource logicAppWorkflow 'Microsoft.Logic/workflows@2019-05-01' = {
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
      parameters: {}
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                threatType: {
                  type: 'string'
                  description: 'Type of security threat detected'
                }
                sourceIP: {
                  type: 'string'
                  description: 'Source IP address of the threat'
                }
                severity: {
                  type: 'string'
                  description: 'Severity level of the threat'
                  enum: [
                    'Low'
                    'Medium'
                    'High'
                    'Critical'
                  ]
                }
                action: {
                  type: 'string'
                  description: 'Recommended action to take'
                  enum: [
                    'block'
                    'alert'
                    'monitor'
                  ]
                }
                timestamp: {
                  type: 'string'
                  description: 'Timestamp of the security event'
                }
              }
              required: [
                'threatType'
                'sourceIP'
                'severity'
                'action'
              ]
            }
          }
        }
      }
      actions: {
        Parse_Security_Event: {
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()'
            schema: {
              type: 'object'
              properties: {
                threatType: {
                  type: 'string'
                }
                sourceIP: {
                  type: 'string'
                }
                severity: {
                  type: 'string'
                }
                action: {
                  type: 'string'
                }
                timestamp: {
                  type: 'string'
                }
              }
            }
          }
        }
        Condition_Check_Action: {
          type: 'If'
          expression: {
            equals: [
              '@body(\'Parse_Security_Event\')?[\'action\']'
              'block'
            ]
          }
          actions: {
            Create_NSG_Block_Rule: {
              type: 'Http'
              inputs: {
                method: 'PUT'
                uri: 'https://management.azure.com/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/networkSecurityGroups/${networkSecurityGroup.name}/securityRules/Block-@{body(\'Parse_Security_Event\')?[\'sourceIP\']}'
                headers: {
                  'Content-Type': 'application/json'
                }
                body: {
                  properties: {
                    priority: 100
                    direction: 'Inbound'
                    access: 'Deny'
                    protocol: '*'
                    sourceAddressPrefix: '@{body(\'Parse_Security_Event\')?[\'sourceIP\']}'
                    destinationAddressPrefix: '*'
                    sourcePortRange: '*'
                    destinationPortRange: '*'
                    description: 'Automated block rule for malicious IP: @{body(\'Parse_Security_Event\')?[\'sourceIP\']}'
                  }
                }
                authentication: {
                  type: 'ManagedServiceIdentity'
                }
              }
            }
            Log_Security_Action: {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: 'https://${logAnalyticsWorkspace.name}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
                headers: {
                  'Content-Type': 'application/json'
                  'Log-Type': 'SecurityOrchestrationEvent'
                }
                body: {
                  ThreatType: '@{body(\'Parse_Security_Event\')?[\'threatType\']}'
                  SourceIP: '@{body(\'Parse_Security_Event\')?[\'sourceIP\']}'
                  Severity: '@{body(\'Parse_Security_Event\')?[\'severity\']}'
                  Action: '@{body(\'Parse_Security_Event\')?[\'action\']}'
                  Timestamp: '@{utcNow()}'
                  WorkflowName: '@{workflow().name}'
                  Status: 'Completed'
                }
                authentication: {
                  type: 'ManagedServiceIdentity'
                }
              }
            }
          }
          else: {
            actions: {
              Log_Security_Event: {
                type: 'Http'
                inputs: {
                  method: 'POST'
                  uri: 'https://${logAnalyticsWorkspace.name}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
                  headers: {
                    'Content-Type': 'application/json'
                    'Log-Type': 'SecurityOrchestrationEvent'
                  }
                  body: {
                    ThreatType: '@{body(\'Parse_Security_Event\')?[\'threatType\']}'
                    SourceIP: '@{body(\'Parse_Security_Event\')?[\'sourceIP\']}'
                    Severity: '@{body(\'Parse_Security_Event\')?[\'severity\']}'
                    Action: '@{body(\'Parse_Security_Event\')?[\'action\']}'
                    Timestamp: '@{utcNow()}'
                    WorkflowName: '@{workflow().name}'
                    Status: 'Logged'
                  }
                  authentication: {
                    type: 'ManagedServiceIdentity'
                  }
                }
              }
            }
          }
        }
        Response: {
          type: 'Response'
          inputs: {
            statusCode: 200
            body: {
              message: 'Security orchestration workflow completed successfully'
              threatType: '@{body(\'Parse_Security_Event\')?[\'threatType\']}'
              action: '@{body(\'Parse_Security_Event\')?[\'action\']}'
              timestamp: '@{utcNow()}'
            }
            headers: {
              'Content-Type': 'application/json'
            }
          }
        }
      }
    }
    parameters: {}
  }
}

// Action Group for Azure Monitor alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'SecOrch'
    enabled: true
    logicAppReceivers: [
      {
        name: 'SecurityOrchestrationLogicApp'
        resourceId: logicAppWorkflow.id
        callbackUrl: listCallbackUrl('${logicAppWorkflow.id}/triggers/manual', '2019-05-01').value
        useCommonAlertSchema: true
      }
    ]
  }
}

// Scheduled Query Rule for suspicious network activity
resource suspiciousNetworkActivityAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'SuspiciousNetworkActivity'
  location: location
  tags: tags
  properties: {
    displayName: 'Suspicious Network Activity Detection'
    description: 'Alert on multiple failed authentication attempts or unusual network patterns'
    severity: 2
    enabled: true
    scopes: [
      logAnalyticsWorkspace.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'SecurityEvent | where EventID == 4625 | summarize FailedAttempts = count() by SourceIP = IpAddress | where FailedAttempts > 10'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// Role Assignment for Logic Apps to modify Network Security Groups
resource logicAppRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, logicAppWorkflow.id, 'NetworkContributor')
  scope: networkSecurityGroup
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7') // Network Contributor
    principalId: logicAppWorkflow.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Logic Apps to write to Log Analytics
resource logicAppLogAnalyticsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, logicAppWorkflow.id, 'LogAnalyticsContributor')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293') // Log Analytics Contributor
    principalId: logicAppWorkflow.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Key Vault access
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, keyVaultAdminObjectId, 'KeyVaultAdministrator')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483') // Key Vault Administrator
    principalId: keyVaultAdminObjectId
    principalType: 'User'
  }
}

// Role Assignment for Logic Apps to access Key Vault
resource logicAppKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, logicAppWorkflow.id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: logicAppWorkflow.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Sample threat intelligence API key secret
resource threatIntelApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ThreatIntelApiKey'
  properties: {
    value: 'sample-threat-intelligence-api-key-replace-with-actual-key'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Diagnostic Settings for Logic Apps (if enabled)
resource logicAppDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'LogicAppDiagnostics'
  scope: logicAppWorkflow
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic Settings for Network Security Group (if enabled)
resource nsgDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'NSGDiagnostics'
  scope: networkSecurityGroup
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'NetworkSecurityGroupEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'NetworkSecurityGroupRuleCounter'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic Settings for Key Vault (if enabled)
resource keyVaultDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'KeyVaultDiagnostics'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'AzurePolicyEvaluationDetails'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic Settings for Storage Account (if enabled)
resource storageAccountDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'StorageAccountDiagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Outputs
@description('The resource ID of the Logic Apps workflow')
output logicAppWorkflowId string = logicAppWorkflow.id

@description('The name of the Logic Apps workflow')
output logicAppWorkflowName string = logicAppWorkflow.name

@description('The trigger URL for the Logic Apps workflow')
@secure()
output logicAppTriggerUrl string = listCallbackUrl('${logicAppWorkflow.id}/triggers/manual', '2019-05-01').value

@description('The resource ID of the Network Security Group')
output networkSecurityGroupId string = networkSecurityGroup.id

@description('The name of the Network Security Group')
output networkSecurityGroupName string = networkSecurityGroup.name

@description('The resource ID of the Virtual Network')
output virtualNetworkId string = virtualNetwork.id

@description('The name of the Virtual Network')
output virtualNetworkName string = virtualNetwork.name

@description('The resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The resource ID of the Storage Account')
output storageAccountId string = storageAccount.id

@description('The name of the Storage Account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceGuid string = logAnalyticsWorkspace.properties.customerId

@description('The resource ID of the Action Group')
output actionGroupId string = actionGroup.id

@description('The name of the Action Group')
output actionGroupName string = actionGroup.name

@description('The resource ID of the Application Security Group')
output applicationSecurityGroupId string = applicationSecurityGroup.id

@description('The name of the Application Security Group')
output applicationSecurityGroupName string = applicationSecurityGroup.name

@description('The principal ID of the Logic Apps managed identity')
output logicAppPrincipalId string = logicAppWorkflow.identity.principalId

@description('The resource names used in the deployment')
output resourceNames object = resourceNames

@description('The resource tags applied to all resources')
output tags object = tags