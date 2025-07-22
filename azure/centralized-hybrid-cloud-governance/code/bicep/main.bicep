// ==============================================================================
// Bicep Template: Centralized Hybrid Cloud Governance with Arc and Policy
// ==============================================================================
// This template creates the Azure infrastructure needed for hybrid cloud governance
// using Azure Arc and Azure Policy across on-premises and multi-cloud environments.
// ==============================================================================

@description('The location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Tags to be applied to all resources')
param tags object = {
  purpose: 'hybrid-governance'
  environment: 'demo'
  solution: 'azure-arc-governance'
}

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Log Analytics workspace pricing tier')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param logAnalyticsPricingTier string = 'PerGB2018'

@description('Enable Azure Policy for Arc-enabled Kubernetes')
param enableKubernetesPolicyExtension bool = true

@description('Enable Azure Monitor for Arc-enabled Kubernetes')
param enableKubernetesMonitoringExtension bool = true

@description('Resource group for Arc-enabled servers')
param arcServersResourceGroup string = resourceGroup().name

@description('Policy assignment enforcement mode')
@allowed([
  'Default'
  'DoNotEnforce'
])
param policyEnforcementMode string = 'Default'

// ==============================================================================
// VARIABLES
// ==============================================================================

var workspaceName = 'law-arc-${uniqueSuffix}'
var policyAssignmentNameServers = 'arc-servers-baseline'
var policyAssignmentNameKubernetes = 'k8s-container-security'
var dataCollectionRuleName = 'dcr-arc-servers-${uniqueSuffix}'
var servicePrincipalName = 'sp-arc-onboarding-${uniqueSuffix}'
var savedQueryName = 'arc-compliance-status'

// Built-in policy set definition ID for Arc-enabled servers security baseline
var arcServersSecurityBaselinePolicySetId = '/providers/Microsoft.Authorization/policySetDefinitions/c96b2f5d-8c94-4588-bb6e-0e1295d5a6d4'

// Built-in policy definition ID for Kubernetes container security
var kubernetesContainerSecurityPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/95edb821-ddaf-4404-9732-666045e056b4'

// ==============================================================================
// LOG ANALYTICS WORKSPACE
// ==============================================================================

@description('Log Analytics workspace for centralized monitoring and compliance reporting')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsPricingTier
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ==============================================================================
// DATA COLLECTION RULE FOR ARC-ENABLED SERVERS
// ==============================================================================

@description('Data Collection Rule for Arc-enabled servers performance monitoring')
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dataCollectionRuleName
  location: location
  tags: tags
  properties: {
    description: 'Data collection rule for Arc-enabled servers monitoring'
    destinations: {
      logAnalytics: [
        {
          name: 'centralWorkspace'
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    dataSources: {
      performanceCounters: [
        {
          name: 'perfCounterDataSource'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available Bytes'
            '\\LogicalDisk(_Total)\\% Free Space'
            '\\Network Interface(*)\\Bytes Total/sec'
            '\\System\\System Up Time'
          ]
        }
      ]
      windowsEventLogs: [
        {
          name: 'windowsEventLogs'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
          ]
        }
      ]
      syslog: [
        {
          name: 'syslogDataSource'
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            'auth'
            'authpriv'
            'cron'
            'daemon'
            'kern'
            'local0'
            'local1'
            'local2'
            'local3'
            'local4'
            'local5'
            'local6'
            'local7'
            'lpr'
            'mail'
            'news'
            'syslog'
            'user'
            'uucp'
          ]
          logLevels: [
            'Alert'
            'Critical'
            'Emergency'
            'Error'
            'Warning'
          ]
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
        ]
        destinations: [
          'centralWorkspace'
        ]
      }
      {
        streams: [
          'Microsoft-Event'
        ]
        destinations: [
          'centralWorkspace'
        ]
      }
      {
        streams: [
          'Microsoft-Syslog'
        ]
        destinations: [
          'centralWorkspace'
        ]
      }
    ]
  }
}

// ==============================================================================
// AZURE POLICY ASSIGNMENTS
// ==============================================================================

@description('Policy assignment for Arc-enabled servers security baseline')
resource arcServersSecurityBaselineAssignment 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: policyAssignmentNameServers
  properties: {
    displayName: 'Security baseline for Arc-enabled servers'
    description: 'This policy assignment applies security baseline policies to Arc-enabled servers'
    enforcementMode: policyEnforcementMode
    policyDefinitionId: arcServersSecurityBaselinePolicySetId
    parameters: {}
    metadata: {
      assignedBy: 'Bicep Template'
      category: 'Security'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
  location: location
}

@description('Policy assignment for Kubernetes container security')
resource kubernetesContainerSecurityAssignment 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: policyAssignmentNameKubernetes
  properties: {
    displayName: 'Kubernetes container security baseline'
    description: 'This policy assignment applies container security policies to Arc-enabled Kubernetes clusters'
    enforcementMode: policyEnforcementMode
    policyDefinitionId: kubernetesContainerSecurityPolicyId
    parameters: {
      effect: {
        value: 'audit'
      }
    }
    metadata: {
      assignedBy: 'Bicep Template'
      category: 'Security'
    }
  }
}

// ==============================================================================
// ROLE ASSIGNMENTS FOR POLICY REMEDIATION
// ==============================================================================

@description('Role assignment for policy assignment managed identity')
resource policyAssignmentRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, policyAssignmentNameServers, 'Contributor')
  properties: {
    principalId: arcServersSecurityBaselineAssignment.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalType: 'ServicePrincipal'
  }
}

// ==============================================================================
// AZURE RESOURCE GRAPH SAVED QUERY
// ==============================================================================

@description('Saved query for Arc compliance monitoring in Azure Resource Graph')
resource arcComplianceSavedQuery 'Microsoft.ResourceGraph/queries@2021-03-01' = {
  name: savedQueryName
  location: 'global'
  tags: tags
  properties: {
    displayName: 'Arc Compliance Status'
    description: 'Monitor compliance status of Arc-enabled resources'
    query: '''
PolicyResources 
| where type =~ 'microsoft.policyinsights/policystates' 
| where properties.resourceType contains 'microsoft.hybridcompute' or properties.resourceType contains 'microsoft.kubernetes' 
| project 
    resourceId=properties.resourceId, 
    complianceState=properties.complianceState, 
    policyDefinitionName=properties.policyDefinitionName, 
    timestamp=properties.timestamp 
| order by timestamp desc
'''
  }
}

// ==============================================================================
// WORKBOOK FOR COMPLIANCE MONITORING
// ==============================================================================

@description('Azure Workbook for Arc compliance monitoring and visualization')
resource arcComplianceWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'arc-compliance-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Arc Hybrid Governance Dashboard'
    description: 'Comprehensive dashboard for monitoring Arc-enabled resources compliance and governance'
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '## Azure Arc Hybrid Governance Dashboard\n\nThis dashboard provides comprehensive monitoring and compliance insights for Azure Arc-enabled resources across your hybrid infrastructure.'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'PolicyResources | where type =~ "microsoft.policyinsights/policystates" | where properties.resourceType contains "microsoft.hybridcompute" or properties.resourceType contains "microsoft.kubernetes" | summarize Total = count(), Compliant = countif(properties.complianceState =~ "Compliant") | project CompliancePercentage = (todouble(Compliant) / todouble(Total)) * 100'
            size: 3
            title: 'Overall Compliance Percentage'
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            visualization: 'singlestat'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'PolicyResources | where type =~ "microsoft.policyinsights/policystates" | where properties.resourceType contains "microsoft.hybridcompute" or properties.resourceType contains "microsoft.kubernetes" | summarize count() by tostring(properties.complianceState)'
            size: 0
            title: 'Compliance Status Distribution'
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            visualization: 'piechart'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'Resources | where type =~ "microsoft.hybridcompute/machines" or type =~ "microsoft.kubernetes/connectedclusters" | summarize count() by type | project ResourceType = case(type =~ "microsoft.hybridcompute/machines", "Arc Servers", "Arc Kubernetes"), Count = count_'
            size: 0
            title: 'Arc-enabled Resources by Type'
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            visualization: 'barchart'
          }
        }
      ]
    })
    category: 'workbook'
    sourceId: logAnalyticsWorkspace.id
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The workspace ID (customer ID) of the Log Analytics workspace')
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The resource ID of the data collection rule for Arc servers')
output dataCollectionRuleId string = dataCollectionRule.id

@description('The name of the data collection rule for Arc servers')
output dataCollectionRuleName string = dataCollectionRule.name

@description('The resource ID of the Arc servers security baseline policy assignment')
output arcServersSecurityBaselinePolicyAssignmentId string = arcServersSecurityBaselineAssignment.id

@description('The resource ID of the Kubernetes container security policy assignment')
output kubernetesContainerSecurityPolicyAssignmentId string = kubernetesContainerSecurityAssignment.id

@description('The principal ID of the policy assignment managed identity')
output policyAssignmentPrincipalId string = arcServersSecurityBaselineAssignment.identity.principalId

@description('The resource ID of the Arc compliance saved query')
output arcComplianceSavedQueryId string = arcComplianceSavedQuery.id

@description('The resource ID of the Arc compliance workbook')
output arcComplianceWorkbookId string = arcComplianceWorkbook.id

@description('Commands to connect Arc-enabled servers (run on target servers)')
output arcServerConnectionCommands object = {
  linux: 'wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh && bash ~/install_linux_azcmagent.sh && sudo azcmagent connect --service-principal-id "<SP_ID>" --service-principal-secret "<SP_SECRET>" --tenant-id "<TENANT_ID>" --subscription-id "${subscription().subscriptionId}" --resource-group "${resourceGroup().name}" --location "${location}"'
  windows: 'Invoke-WebRequest -Uri https://aka.ms/azcmagent -OutFile "$env:TEMP\\install_windows_azcmagent.ps1" && & "$env:TEMP\\install_windows_azcmagent.ps1" && & "$env:ProgramFiles\\AzureConnectedMachineAgent\\azcmagent.exe" connect --service-principal-id "<SP_ID>" --service-principal-secret "<SP_SECRET>" --tenant-id "<TENANT_ID>" --subscription-id "${subscription().subscriptionId}" --resource-group "${resourceGroup().name}" --location "${location}"'
}

@description('Sample Azure Resource Graph queries for compliance monitoring')
output sampleResourceGraphQueries object = {
  allArcResources: 'Resources | where type =~ "microsoft.hybridcompute/machines" or type =~ "microsoft.kubernetes/connectedclusters" | project name, type, location, resourceGroup, subscriptionId | order by type asc'
  complianceStatus: 'PolicyResources | where type =~ "microsoft.policyinsights/policystates" | where properties.resourceType contains "microsoft.hybridcompute" or properties.resourceType contains "microsoft.kubernetes" | summarize count() by tostring(properties.complianceState)'
  nonCompliantResources: 'PolicyResources | where type =~ "microsoft.policyinsights/policystates" | where properties.resourceType contains "microsoft.hybridcompute" or properties.resourceType contains "microsoft.kubernetes" | where properties.complianceState =~ "NonCompliant" | project resourceId=properties.resourceId, policyDefinitionName=properties.policyDefinitionName, complianceState=properties.complianceState'
}

@description('Next steps for completing the Arc setup')
output nextSteps array = [
  'Create a service principal for Arc server onboarding using: az ad sp create-for-rbac --name sp-arc-onboarding --role "Azure Connected Machine Onboarding" --scopes /subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}'
  'Connect Kubernetes clusters to Arc using: az connectedk8s connect --name <cluster-name> --resource-group ${resourceGroup().name}'
  'Enable Azure Policy extension on Arc-enabled Kubernetes: az k8s-extension create --name azurepolicy --cluster-name <cluster-name> --resource-group ${resourceGroup().name} --cluster-type connectedClusters --extension-type Microsoft.PolicyInsights'
  'Enable Azure Monitor extension on Arc-enabled Kubernetes: az k8s-extension create --name azuremonitor-containers --cluster-name <cluster-name> --resource-group ${resourceGroup().name} --cluster-type connectedClusters --extension-type Microsoft.AzureMonitor.Containers'
  'View compliance status in Azure Portal: https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyMenuBlade/Compliance'
  'Access the Arc compliance workbook in Azure Portal to monitor governance metrics'
]