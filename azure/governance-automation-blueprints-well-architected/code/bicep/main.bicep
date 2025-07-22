// ==============================================================================
// Azure Blueprints Enterprise Governance Automation - Main Bicep Template
// ==============================================================================
// This template implements enterprise-grade governance automation using Azure 
// Blueprints, Azure Policy, and Well-Architected Framework principles.
// ==============================================================================

@description('Primary deployment region for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Environment designation (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'prod'

@description('Cost center identifier for resource tagging and billing')
param costCenter string = 'IT'

@description('Resource owner for governance and accountability')
param ownerEmail string = 'governance@company.com'

@description('Log Analytics workspace retention period in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Enable diagnostic settings for all resources')
param enableDiagnostics bool = true

@description('Enable Azure Advisor recommendations and alerts')
param enableAdvisorAlerts bool = true

@description('Storage account SKU for compliance storage')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param storageAccountSku string = 'Standard_LRS'

// ==============================================================================
// VARIABLES
// ==============================================================================

var resourceNames = {
  logAnalyticsWorkspace: 'law-governance-${resourceSuffix}'
  storageAccount: 'stgovern${resourceSuffix}'
  actionGroup: 'ag-governance-${resourceSuffix}'
  dashboard: 'dash-governance-${resourceSuffix}'
  userAssignedIdentity: 'id-governance-${resourceSuffix}'
  policyAssignment: 'pa-governance-${resourceSuffix}'
  roleAssignment: 'ra-governance-${resourceSuffix}'
}

var commonTags = {
  Environment: environment
  CostCenter: costCenter
  Owner: ownerEmail
  Purpose: 'Governance'
  Framework: 'Well-Architected'
  'Created-By': 'Azure-Bicep'
}

var policyDefinitions = {
  requireTags: {
    name: 'require-resource-tags-${resourceSuffix}'
    displayName: 'Require specific tags on resources'
    description: 'Enforces required tags for cost tracking and governance'
    mode: 'All'
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Resources/subscriptions/resourceGroups'
          }
          {
            anyOf: [
              {
                field: 'tags[\'Environment\']'
                exists: false
              }
              {
                field: 'tags[\'CostCenter\']'
                exists: false
              }
              {
                field: 'tags[\'Owner\']'
                exists: false
              }
            ]
          }
        ]
      }
      then: {
        effect: 'deny'
      }
    }
  }
}

// ==============================================================================
// MANAGED IDENTITY FOR GOVERNANCE OPERATIONS
// ==============================================================================

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: resourceNames.userAssignedIdentity
  location: location
  tags: commonTags
}

// ==============================================================================
// LOG ANALYTICS WORKSPACE FOR GOVERNANCE MONITORING
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ==============================================================================
// COMPLIANCE STORAGE ACCOUNT
// ==============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: union(commonTags, {
    Compliance: 'Required'
    'Data-Classification': 'Internal'
  })
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: true
    accessTier: 'Hot'
    encryption: {
      requireInfrastructureEncryption: true
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
        queue: {
          enabled: true
          keyType: 'Service'
        }
        table: {
          enabled: true
          keyType: 'Service'
        }
      }
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Blob service configuration for compliance storage
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    versioning: {
      enabled: true
    }
    changeFeed: {
      enabled: true
      retentionInDays: 30
    }
  }
}

// Container for governance artifacts
resource governanceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'governance-artifacts'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'governance-artifacts'
      retention: '7-years'
    }
  }
}

// ==============================================================================
// CUSTOM POLICY DEFINITIONS
// ==============================================================================

resource customPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: policyDefinitions.requireTags.name
  properties: {
    displayName: policyDefinitions.requireTags.displayName
    description: policyDefinitions.requireTags.description
    policyType: 'Custom'
    mode: policyDefinitions.requireTags.mode
    policyRule: policyDefinitions.requireTags.policyRule
    parameters: {}
    metadata: {
      category: 'Governance'
      createdBy: 'Azure-Bicep'
      createdOn: utcNow()
    }
  }
}

// ==============================================================================
// POLICY INITIATIVE (POLICY SET) DEFINITION
// ==============================================================================

resource policyInitiative 'Microsoft.Authorization/policySetDefinitions@2023-04-01' = {
  name: 'enterprise-security-initiative-${resourceSuffix}'
  properties: {
    displayName: 'Enterprise Security and Governance Initiative'
    description: 'Comprehensive security policies aligned with Well-Architected Framework'
    policyType: 'Custom'
    metadata: {
      category: 'Security'
      createdBy: 'Azure-Bicep'
      createdOn: utcNow()
    }
    parameters: {}
    policyDefinitions: [
      {
        policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9'
        policyDefinitionReferenceId: 'RequireSecureTransfer'
        parameters: {}
        groupNames: []
      }
      {
        policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/1e30110a-5ceb-460c-a204-c1c3969c6d62'
        policyDefinitionReferenceId: 'RequireStorageEncryption'
        parameters: {}
        groupNames: []
      }
      {
        policyDefinitionId: customPolicyDefinition.id
        policyDefinitionReferenceId: 'RequireResourceTags'
        parameters: {}
        groupNames: []
      }
    ]
    policyDefinitionGroups: [
      {
        name: 'Security'
        displayName: 'Security Controls'
        description: 'Policies that enforce security best practices'
      }
      {
        name: 'Governance'
        displayName: 'Governance Controls'
        description: 'Policies that enforce governance and compliance'
      }
    ]
  }
}

// ==============================================================================
// POLICY ASSIGNMENT
// ==============================================================================

resource policyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: resourceNames.policyAssignment
  properties: {
    displayName: 'Enterprise Governance Policy Assignment'
    description: 'Assigns enterprise governance policies to ensure compliance'
    policyDefinitionId: policyInitiative.id
    parameters: {}
    enforcementMode: 'Default'
    identity: {
      type: 'UserAssigned'
      userAssignedIdentities: {
        '${userAssignedIdentity.id}': {}
      }
    }
    metadata: {
      assignedBy: 'Azure-Bicep'
      assignedOn: utcNow()
    }
  }
  location: location
}

// ==============================================================================
// ROLE ASSIGNMENTS FOR GOVERNANCE
// ==============================================================================

// Policy Contributor role for managed identity
resource policyContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, userAssignedIdentity.id, 'Policy Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Allows managed identity to contribute to policy definitions and assignments'
  }
}

// Storage Account Contributor role for compliance storage
resource storageContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, userAssignedIdentity.id, 'Storage Account Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Allows managed identity to manage compliance storage account'
  }
}

// ==============================================================================
// ACTION GROUP FOR GOVERNANCE ALERTS
// ==============================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'global'
  tags: commonTags
  properties: {
    groupShortName: 'GovAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'governance-team'
        emailAddress: ownerEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    eventHubReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// ==============================================================================
// ACTIVITY LOG ALERTS FOR GOVERNANCE
// ==============================================================================

resource advisorSecurityAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = if (enableAdvisorAlerts) {
  name: 'advisor-security-alert-${resourceSuffix}'
  location: 'global'
  tags: commonTags
  properties: {
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Recommendation'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Advisor/recommendations/available/action'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
          webhookProperties: {}
        }
      ]
    }
    description: 'Alert for high-impact security recommendations from Azure Advisor'
  }
}

// Policy compliance alert
resource policyComplianceAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'policy-compliance-alert-${resourceSuffix}'
  location: 'global'
  tags: commonTags
  properties: {
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Policy'
        }
        {
          field: 'level'
          equals: 'Error'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
          webhookProperties: {}
        }
      ]
    }
    description: 'Alert for policy compliance violations'
  }
}

// ==============================================================================
// DIAGNOSTIC SETTINGS
// ==============================================================================

resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'Capacity'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    logs: []
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Resource group ID where all resources were deployed')
output resourceGroupId string = resourceGroup().id

@description('Log Analytics workspace ID for governance monitoring')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Storage account ID for compliance artifacts')
output storageAccountId string = storageAccount.id

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Primary endpoints for the storage account')
output storageAccountEndpoints object = storageAccount.properties.primaryEndpoints

@description('User-assigned managed identity ID for governance operations')
output userAssignedIdentityId string = userAssignedIdentity.id

@description('User-assigned managed identity principal ID')
output userAssignedIdentityPrincipalId string = userAssignedIdentity.properties.principalId

@description('Custom policy definition ID for required tags')
output customPolicyDefinitionId string = customPolicyDefinition.id

@description('Policy initiative (set) definition ID')
output policyInitiativeId string = policyInitiative.id

@description('Policy assignment ID')
output policyAssignmentId string = policyAssignment.id

@description('Action group ID for governance alerts')
output actionGroupId string = actionGroup.id

@description('Governance container URL for artifact storage')
output governanceContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}${governanceContainer.name}'

@description('Resource naming convention used')
output resourceNames object = resourceNames

@description('Common tags applied to all resources')
output commonTags object = commonTags

@description('Deployment timestamp')
output deploymentTimestamp string = utcNow()

@description('Azure region where resources were deployed')
output deploymentLocation string = location

@description('Environment designation')
output environment string = environment

@description('Next steps for completing governance setup')
output nextSteps array = [
  'Review and customize policy definitions in the Azure portal'
  'Configure additional Azure Advisor recommendations'
  'Set up governance dashboard with custom queries'
  'Configure blueprint assignments for additional subscriptions'
  'Review compliance status and adjust policies as needed'
]