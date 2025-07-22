// =============================================================================
// Azure Policy and Resource Graph Governance Solution
// =============================================================================
// This Bicep template deploys a comprehensive governance solution for automated
// resource tagging and compliance enforcement using Azure Policy and Resource Graph.
//
// Features:
// - Custom policy definitions for mandatory tags
// - Policy initiative for comprehensive tag governance
// - Policy assignment with remediation tasks
// - Log Analytics workspace for compliance monitoring
// - Azure Automation account for remediation workflows
// - Azure Monitor integration for compliance tracking
// - Resource Graph shared queries for compliance reporting
// =============================================================================

@description('Primary Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment designation (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource naming to avoid conflicts')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Required tags that must be present on all resources')
param requiredTags object = {
  Department: 'IT'
  Environment: environment
  CostCenter: 'CC001'
}

@description('Resource types to exclude from tagging requirements')
param excludedResourceTypes array = [
  'Microsoft.Network/networkSecurityGroups'
  'Microsoft.Network/routeTables'
  'Microsoft.Storage/storageAccounts/blobServices'
  'Microsoft.Storage/storageAccounts/fileServices'
]

@description('Enable automatic remediation for non-compliant resources')
param enableRemediation bool = true

@description('Log Analytics workspace retention period in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('Tags to be applied to all resources created by this template')
param resourceTags object = {
  Purpose: 'Governance'
  Environment: environment
  CreatedBy: 'Bicep'
  Solution: 'TaggingCompliance'
}

// =============================================================================
// VARIABLES
// =============================================================================

var resourceNames = {
  logAnalyticsWorkspace: 'law-governance-${resourceSuffix}'
  automationAccount: 'aa-governance-${resourceSuffix}'
  policyInitiative: 'mandatory-tagging-initiative-${resourceSuffix}'
  policyAssignment: 'enforce-mandatory-tags-${resourceSuffix}'
  userAssignedIdentity: 'uai-governance-${resourceSuffix}'
  actionGroup: 'ag-governance-${resourceSuffix}'
  alertRule: 'ar-tag-violations-${resourceSuffix}'
}

var policyDefinitions = [
  {
    name: 'require-department-tag'
    displayName: 'Require Department Tag on Resources'
    description: 'Ensures all resources have a Department tag with allowed values'
    effect: 'deny'
    tagName: 'Department'
    allowedValues: ['IT', 'Finance', 'HR', 'Operations', 'Development']
  }
  {
    name: 'require-environment-tag'
    displayName: 'Require Environment Tag on Resources'
    description: 'Ensures all resources have an Environment tag with allowed values'
    effect: 'deny'
    tagName: 'Environment'
    allowedValues: ['dev', 'staging', 'prod']
  }
  {
    name: 'inherit-costcenter-tag'
    displayName: 'Inherit CostCenter Tag from Resource Group'
    description: 'Automatically applies CostCenter tag from parent resource group'
    effect: 'modify'
    tagName: 'CostCenter'
    allowedValues: []
  }
]

// =============================================================================
// MANAGED IDENTITY FOR POLICY ASSIGNMENTS
// =============================================================================

@description('User-assigned managed identity for policy assignments and remediation')
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: resourceNames.userAssignedIdentity
  location: location
  tags: resourceTags
}

// =============================================================================
// LOG ANALYTICS WORKSPACE
// =============================================================================

@description('Log Analytics workspace for compliance monitoring and policy evaluation logs')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: resourceTags
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
  }
}

// =============================================================================
// AZURE AUTOMATION ACCOUNT
// =============================================================================

@description('Azure Automation account for remediation workflows and runbooks')
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: resourceNames.automationAccount
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'Basic'
    }
    disableLocalAuth: false
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
}

// =============================================================================
// AZURE MONITOR ACTION GROUP
// =============================================================================

@description('Action group for governance alerts and notifications')
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'Global'
  tags: resourceTags
  properties: {
    groupShortName: 'governance'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureFunction: []
    logicAppReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    armRoleReceivers: []
    azureFunctionReceivers: []
    eventHubReceivers: []
  }
}

// =============================================================================
// CUSTOM POLICY DEFINITIONS
// =============================================================================

@description('Custom policy definition for requiring Department tag')
resource requireDepartmentTagPolicy 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: policyDefinitions[0].name
  properties: {
    policyType: 'Custom'
    mode: 'Indexed'
    displayName: policyDefinitions[0].displayName
    description: policyDefinitions[0].description
    metadata: {
      category: 'Tags'
      createdBy: 'Bicep'
      createdDate: utcNow()
    }
    parameters: {
      tagName: {
        type: 'String'
        metadata: {
          displayName: 'Tag Name'
          description: 'Name of the tag to enforce'
        }
        defaultValue: policyDefinitions[0].tagName
      }
      allowedValues: {
        type: 'Array'
        metadata: {
          displayName: 'Allowed Values'
          description: 'List of allowed values for the tag'
        }
        defaultValue: policyDefinitions[0].allowedValues
      }
      excludedResourceTypes: {
        type: 'Array'
        metadata: {
          displayName: 'Excluded Resource Types'
          description: 'Resource types to exclude from this policy'
        }
        defaultValue: excludedResourceTypes
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            notIn: '[parameters(\'excludedResourceTypes\')]'
          }
          {
            anyOf: [
              {
                field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
                exists: false
              }
              {
                field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
                notIn: '[parameters(\'allowedValues\')]'
              }
            ]
          }
        ]
      }
      then: {
        effect: policyDefinitions[0].effect
      }
    }
  }
}

@description('Custom policy definition for requiring Environment tag')
resource requireEnvironmentTagPolicy 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: policyDefinitions[1].name
  properties: {
    policyType: 'Custom'
    mode: 'Indexed'
    displayName: policyDefinitions[1].displayName
    description: policyDefinitions[1].description
    metadata: {
      category: 'Tags'
      createdBy: 'Bicep'
      createdDate: utcNow()
    }
    parameters: {
      tagName: {
        type: 'String'
        metadata: {
          displayName: 'Tag Name'
          description: 'Name of the tag to enforce'
        }
        defaultValue: policyDefinitions[1].tagName
      }
      allowedValues: {
        type: 'Array'
        metadata: {
          displayName: 'Allowed Values'
          description: 'List of allowed values for the tag'
        }
        defaultValue: policyDefinitions[1].allowedValues
      }
      excludedResourceTypes: {
        type: 'Array'
        metadata: {
          displayName: 'Excluded Resource Types'
          description: 'Resource types to exclude from this policy'
        }
        defaultValue: excludedResourceTypes
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            notIn: '[parameters(\'excludedResourceTypes\')]'
          }
          {
            anyOf: [
              {
                field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
                exists: false
              }
              {
                field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
                notIn: '[parameters(\'allowedValues\')]'
              }
            ]
          }
        ]
      }
      then: {
        effect: policyDefinitions[1].effect
      }
    }
  }
}

@description('Custom policy definition for inheriting CostCenter tag from resource group')
resource inheritCostCenterTagPolicy 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: policyDefinitions[2].name
  properties: {
    policyType: 'Custom'
    mode: 'Indexed'
    displayName: policyDefinitions[2].displayName
    description: policyDefinitions[2].description
    metadata: {
      category: 'Tags'
      createdBy: 'Bicep'
      createdDate: utcNow()
    }
    parameters: {
      tagName: {
        type: 'String'
        metadata: {
          displayName: 'Tag Name'
          description: 'Name of the tag to inherit'
        }
        defaultValue: policyDefinitions[2].tagName
      }
      excludedResourceTypes: {
        type: 'Array'
        metadata: {
          displayName: 'Excluded Resource Types'
          description: 'Resource types to exclude from this policy'
        }
        defaultValue: excludedResourceTypes
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            notIn: '[parameters(\'excludedResourceTypes\')]'
          }
          {
            field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
            exists: false
          }
          {
            value: '[resourceGroup().tags[parameters(\'tagName\')]]'
            notEquals: ''
          }
        ]
      }
      then: {
        effect: policyDefinitions[2].effect
        details: {
          roleDefinitionIds: [
            '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
          ]
          operations: [
            {
              operation: 'add'
              field: '[concat(\'tags[\', parameters(\'tagName\'), \']\')]'
              value: '[resourceGroup().tags[parameters(\'tagName\')]]'
            }
          ]
        }
      }
    }
  }
}

// =============================================================================
// POLICY INITIATIVE (POLICY SET DEFINITION)
// =============================================================================

@description('Policy initiative combining all tagging policies for comprehensive governance')
resource policyInitiative 'Microsoft.Authorization/policySetDefinitions@2023-04-01' = {
  name: resourceNames.policyInitiative
  properties: {
    policyType: 'Custom'
    displayName: 'Mandatory Resource Tagging Initiative'
    description: 'Comprehensive tagging policy initiative for governance and compliance'
    metadata: {
      category: 'Tags'
      createdBy: 'Bicep'
      createdDate: utcNow()
    }
    parameters: {
      excludedResourceTypes: {
        type: 'Array'
        metadata: {
          displayName: 'Excluded Resource Types'
          description: 'Resource types to exclude from tagging requirements'
        }
        defaultValue: excludedResourceTypes
      }
      requiredTags: {
        type: 'Object'
        metadata: {
          displayName: 'Required Tags'
          description: 'Object containing required tags and their allowed values'
        }
        defaultValue: requiredTags
      }
    }
    policyDefinitions: [
      {
        policyDefinitionId: requireDepartmentTagPolicy.id
        parameters: {
          excludedResourceTypes: {
            value: '[parameters(\'excludedResourceTypes\')]'
          }
        }
        policyDefinitionReferenceId: 'require-department-tag'
      }
      {
        policyDefinitionId: requireEnvironmentTagPolicy.id
        parameters: {
          excludedResourceTypes: {
            value: '[parameters(\'excludedResourceTypes\')]'
          }
        }
        policyDefinitionReferenceId: 'require-environment-tag'
      }
      {
        policyDefinitionId: inheritCostCenterTagPolicy.id
        parameters: {
          excludedResourceTypes: {
            value: '[parameters(\'excludedResourceTypes\')]'
          }
        }
        policyDefinitionReferenceId: 'inherit-costcenter-tag'
      }
    ]
  }
}

// =============================================================================
// POLICY ASSIGNMENT
// =============================================================================

@description('Policy assignment to enforce mandatory tagging at resource group scope')
resource policyAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: resourceNames.policyAssignment
  properties: {
    displayName: 'Enforce Mandatory Tags - Resource Group Level'
    description: 'Resource group level enforcement of mandatory tagging requirements'
    policyDefinitionId: policyInitiative.id
    enforcementMode: 'Default'
    parameters: {
      excludedResourceTypes: {
        value: excludedResourceTypes
      }
      requiredTags: {
        value: requiredTags
      }
    }
    metadata: {
      createdBy: 'Bicep'
      createdDate: utcNow()
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  location: location
}

// =============================================================================
// REMEDIATION TASK
// =============================================================================

@description('Remediation task for automatically correcting non-compliant resources')
resource remediationTask 'Microsoft.PolicyInsights/remediations@2021-10-01' = if (enableRemediation) {
  name: 'remediate-missing-tags-${resourceSuffix}'
  properties: {
    policyAssignmentId: policyAssignment.id
    policyDefinitionReferenceId: 'inherit-costcenter-tag'
    resourceDiscoveryMode: 'ExistingNonCompliant'
    parallelDeployments: 10
    resourceCount: 100
  }
}

// =============================================================================
// RESOURCE GRAPH SHARED QUERIES
// =============================================================================

@description('Shared query for comprehensive tag compliance monitoring')
resource tagComplianceQuery 'Microsoft.ResourceGraph/queries@2024-04-01' = {
  name: 'tag-compliance-dashboard'
  location: 'Global'
  tags: resourceTags
  properties: {
    displayName: 'Tag Compliance Dashboard Query'
    description: 'Comprehensive tag compliance monitoring query for governance reporting'
    query: '''
      Resources
      | where type !in ('microsoft.resources/subscriptions', 'microsoft.resources/resourcegroups')
      | extend compliance = case(
          tags.Department != '' and isnotempty(tags.Department) and 
          tags.Environment != '' and isnotempty(tags.Environment) and
          tags.CostCenter != '' and isnotempty(tags.CostCenter), 'Fully Compliant',
          tags.Department != '' and isnotempty(tags.Department) or 
          tags.Environment != '' and isnotempty(tags.Environment) or
          tags.CostCenter != '' and isnotempty(tags.CostCenter), 'Partially Compliant',
          'Non-Compliant'
      )
      | extend resourceType = tostring(type)
      | extend resourceName = tostring(name)
      | extend resourceGroup = tostring(resourceGroup)
      | extend location = tostring(location)
      | project resourceName, resourceType, resourceGroup, location, compliance, tags
      | order by compliance desc, resourceType asc
    '''
  }
}

@description('Shared query for compliance summary by resource type')
resource complianceSummaryQuery 'Microsoft.ResourceGraph/queries@2024-04-01' = {
  name: 'compliance-summary-by-type'
  location: 'Global'
  tags: resourceTags
  properties: {
    displayName: 'Compliance Summary by Resource Type'
    description: 'Summarized compliance statistics grouped by resource type'
    query: '''
      Resources
      | where type !in ('microsoft.resources/subscriptions', 'microsoft.resources/resourcegroups')
      | extend hasDepartment = iff(tags.Department != '' and isnotempty(tags.Department), 'Compliant', 'Non-Compliant')
      | extend hasEnvironment = iff(tags.Environment != '' and isnotempty(tags.Environment), 'Compliant', 'Non-Compliant')
      | extend hasCostCenter = iff(tags.CostCenter != '' and isnotempty(tags.CostCenter), 'Compliant', 'Non-Compliant')
      | summarize 
          TotalResources = count(),
          DepartmentCompliant = countif(hasDepartment == 'Compliant'),
          EnvironmentCompliant = countif(hasEnvironment == 'Compliant'),
          CostCenterCompliant = countif(hasCostCenter == 'Compliant')
      by type
      | extend DepartmentCompliancePercent = round(todouble(DepartmentCompliant) / todouble(TotalResources) * 100, 2)
      | extend EnvironmentCompliancePercent = round(todouble(EnvironmentCompliant) / todouble(TotalResources) * 100, 2)
      | extend CostCenterCompliancePercent = round(todouble(CostCenterCompliant) / todouble(TotalResources) * 100, 2)
      | order by TotalResources desc
    '''
  }
}

// =============================================================================
// DIAGNOSTIC SETTINGS
// =============================================================================

@description('Diagnostic settings for policy evaluation logging')
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'policy-compliance-logs'
  scope: resourceGroup()
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'Administrative'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'Policy'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// =============================================================================
// RBAC ASSIGNMENTS
// =============================================================================

@description('Role assignment for the managed identity to have Contributor access')
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(userAssignedIdentity.id, 'Contributor', resourceGroup().id)
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    description: 'Contributor role for policy remediation managed identity'
  }
}

@description('Role assignment for the managed identity to have Policy Contributor access')
resource policyContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(userAssignedIdentity.id, 'Policy Contributor', resourceGroup().id)
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
    description: 'Policy Contributor role for policy remediation managed identity'
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('Resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Resource ID of the Azure Automation account')
output automationAccountId string = automationAccount.id

@description('Name of the Azure Automation account')
output automationAccountName string = automationAccount.name

@description('Resource ID of the policy initiative')
output policyInitiativeId string = policyInitiative.id

@description('Name of the policy initiative')
output policyInitiativeName string = policyInitiative.name

@description('Resource ID of the policy assignment')
output policyAssignmentId string = policyAssignment.id

@description('Name of the policy assignment')
output policyAssignmentName string = policyAssignment.name

@description('Resource ID of the user-assigned managed identity')
output userAssignedIdentityId string = userAssignedIdentity.id

@description('Principal ID of the user-assigned managed identity')
output userAssignedIdentityPrincipalId string = userAssignedIdentity.properties.principalId

@description('Resource ID of the remediation task')
output remediationTaskId string = enableRemediation ? remediationTask.id : ''

@description('Names of the custom policy definitions created')
output policyDefinitionNames array = [
  requireDepartmentTagPolicy.name
  requireEnvironmentTagPolicy.name
  inheritCostCenterTagPolicy.name
]

@description('Resource IDs of the Resource Graph shared queries')
output sharedQueryIds array = [
  tagComplianceQuery.id
  complianceSummaryQuery.id
]

@description('Action group ID for governance alerts')
output actionGroupId string = actionGroup.id

@description('Commands to verify the deployment')
output verificationCommands array = [
  'az policy assignment show --name ${policyAssignment.name} --scope ${resourceGroup().id}'
  'az policy state list --policy-assignment ${policyAssignment.name}'
  'az graph query -q "Resources | where type !in (\'microsoft.resources/subscriptions\', \'microsoft.resources/resourcegroups\') | extend compliance = case(tags.Department != \'\' and isnotempty(tags.Department) and tags.Environment != \'\' and isnotempty(tags.Environment), \'Fully Compliant\', \'Non-Compliant\') | summarize count() by compliance"'
  'az monitor log-analytics workspace show --resource-group ${resourceGroup().name} --workspace-name ${logAnalyticsWorkspace.name}'
]

@description('Resource information for monitoring and management')
output resourceInfo object = {
  resourceGroupName: resourceGroup().name
  location: location
  environment: environment
  resourceSuffix: resourceSuffix
  deploymentTimestamp: utcNow()
  requiredTags: requiredTags
  excludedResourceTypes: excludedResourceTypes
  logRetentionDays: logRetentionDays
  remediationEnabled: enableRemediation
}