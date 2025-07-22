@description('Comprehensive Azure security incident response infrastructure using Azure Unified Operations and Azure Monitor Workbooks')

// =============================================================================
// PARAMETERS
// =============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Log Analytics workspace pricing tier')
@allowed(['PerGB2018', 'Free', 'Standalone', 'PerNode', 'Standard', 'Premium'])
param workspacePricingTier string = 'PerGB2018'

@description('Log Analytics workspace data retention in days')
@minValue(30)
@maxValue(730)
param workspaceRetentionDays int = 90

@description('Enable User and Entity Behavior Analytics (UEBA)')
param enableUEBA bool = true

@description('Enable automated response playbooks')
param enableAutomation bool = true

@description('Notification email for high severity incidents')
param notificationEmail string = ''

@description('Slack webhook URL for notifications (optional)')
param slackWebhookUrl string = ''

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'security-operations'
  environment: environment
  solution: 'unified-security-operations'
  managedBy: 'bicep'
}

// =============================================================================
// VARIABLES
// =============================================================================

var namingPrefix = 'sec-ops'
var workspaceName = '${namingPrefix}-law-${uniqueSuffix}'
var sentinelName = '${namingPrefix}-sentinel-${uniqueSuffix}'
var automationAccountName = '${namingPrefix}-automation-${uniqueSuffix}'
var logicAppName = '${namingPrefix}-logic-${uniqueSuffix}'
var playbookName = '${namingPrefix}-playbook-${uniqueSuffix}'
var workbookName = '${namingPrefix}-workbook-${uniqueSuffix}'
var keyVaultName = '${namingPrefix}-kv-${uniqueSuffix}'
var managedIdentityName = '${namingPrefix}-identity-${uniqueSuffix}'

// Security analytics rules configuration
var analyticsRules = [
  {
    name: 'Multiple Failed Sign-in Attempts'
    displayName: 'Multiple Failed Sign-in Attempts'
    description: 'Detects multiple failed sign-in attempts from same user indicating potential brute force attack'
    severity: 'Medium'
    query: 'SigninLogs | where ResultType != 0 | summarize FailedAttempts = count() by UserPrincipalName, bin(TimeGenerated, 5m) | where FailedAttempts >= 5'
    queryFrequency: 'PT5M'
    queryPeriod: 'PT5M'
    triggerThreshold: 0
    tactics: ['CredentialAccess']
  }
  {
    name: 'Privilege Escalation Detected'
    displayName: 'Privilege Escalation Detected'
    description: 'Detects potential privilege escalation activities including role assignments and permissions changes'
    severity: 'High'
    query: 'AuditLogs | where OperationName in ("Add member to role", "Add app role assignment") | where ResultType == "success"'
    queryFrequency: 'PT10M'
    queryPeriod: 'PT10M'
    triggerThreshold: 0
    tactics: ['PrivilegeEscalation']
  }
  {
    name: 'Suspicious Azure Activity'
    displayName: 'Suspicious Azure Activity'
    description: 'Detects suspicious Azure resource management activities outside normal business hours'
    severity: 'Medium'
    query: 'AzureActivity | where TimeGenerated > ago(1h) | where ActivityStatus == "Succeeded" | where OperationName has_any ("delete", "create") | extend Hour = datetime_part("hour", TimeGenerated) | where Hour < 6 or Hour > 22'
    queryFrequency: 'PT1H'
    queryPeriod: 'PT1H'
    triggerThreshold: 0
    tactics: ['Impact']
  }
]

// Data connector configuration
var dataConnectors = [
  {
    name: 'AzureActiveDirectory'
    kind: 'AzureActiveDirectory'
    dataTypes: {
      signInLogs: { state: 'Enabled' }
      auditLogs: { state: 'Enabled' }
    }
  }
  {
    name: 'AzureActivity'
    kind: 'AzureActivity'
    dataTypes: {
      azureActivity: { state: 'Enabled' }
    }
  }
  {
    name: 'SecurityEvents'
    kind: 'SecurityEvents'
    dataTypes: {
      securityEvents: { state: 'Enabled' }
    }
  }
  {
    name: 'Office365'
    kind: 'Office365'
    dataTypes: {
      exchange: { state: 'Enabled' }
      sharePoint: { state: 'Enabled' }
      teams: { state: 'Enabled' }
    }
  }
]

// =============================================================================
// RESOURCES
// =============================================================================

// Managed Identity for automation and cross-resource access
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Key Vault for storing secrets and credentials
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
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: managedIdentity.properties.principalId
        permissions: {
          secrets: [
            'get'
            'list'
            'set'
          ]
        }
      }
    ]
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store notification email in Key Vault if provided
resource emailSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(notificationEmail)) {
  parent: keyVault
  name: 'notification-email'
  properties: {
    value: notificationEmail
    contentType: 'text/plain'
  }
}

// Store Slack webhook URL in Key Vault if provided
resource slackSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(slackWebhookUrl)) {
  parent: keyVault
  name: 'slack-webhook-url'
  properties: {
    value: slackWebhookUrl
    contentType: 'text/plain'
  }
}

// Log Analytics Workspace - Foundation for Microsoft Sentinel
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: workspacePricingTier
    }
    retentionInDays: workspaceRetentionDays
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

// Microsoft Sentinel - Cloud-native SIEM solution
resource sentinelSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${logAnalyticsWorkspace.name})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'SecurityInsights(${logAnalyticsWorkspace.name})'
    publisher: 'Microsoft'
    product: 'OMSGallery/SecurityInsights'
    promotionCode: ''
  }
}

// Enable UEBA (User and Entity Behavior Analytics)
resource uebaSettings 'Microsoft.SecurityInsights/settings@2023-02-01' = if (enableUEBA) {
  scope: logAnalyticsWorkspace
  name: 'Ueba'
  kind: 'Ueba'
  properties: {
    dataSources: [
      'AuditLogs'
      'AzureActivity'
      'SecurityEvent'
      'SigninLogs'
    ]
  }
  dependsOn: [
    sentinelSolution
  ]
}

// Data Connectors - Enable data ingestion from various sources
resource dataConnectorAzureAD 'Microsoft.SecurityInsights/dataConnectors@2023-02-01' = {
  scope: logAnalyticsWorkspace
  name: 'azuread-connector'
  kind: 'AzureActiveDirectory'
  properties: {
    dataTypes: {
      signInLogs: {
        state: 'Enabled'
      }
      auditLogs: {
        state: 'Enabled'
      }
    }
    tenantId: subscription().tenantId
  }
  dependsOn: [
    sentinelSolution
  ]
}

resource dataConnectorAzureActivity 'Microsoft.SecurityInsights/dataConnectors@2023-02-01' = {
  scope: logAnalyticsWorkspace
  name: 'azureactivity-connector'
  kind: 'AzureActivity'
  properties: {
    dataTypes: {
      azureActivity: {
        state: 'Enabled'
      }
    }
    subscriptionId: subscription().subscriptionId
  }
  dependsOn: [
    sentinelSolution
  ]
}

resource dataConnectorSecurityEvents 'Microsoft.SecurityInsights/dataConnectors@2023-02-01' = {
  scope: logAnalyticsWorkspace
  name: 'securityevents-connector'
  kind: 'SecurityEvents'
  properties: {
    dataTypes: {
      securityEvents: {
        state: 'Enabled'
      }
    }
  }
  dependsOn: [
    sentinelSolution
  ]
}

// Analytics Rules - Define threat detection logic
resource analyticsRule1 'Microsoft.SecurityInsights/alertRules@2023-02-01' = {
  scope: logAnalyticsWorkspace
  name: 'failed-signin-rule'
  kind: 'Scheduled'
  properties: {
    displayName: analyticsRules[0].displayName
    description: analyticsRules[0].description
    severity: analyticsRules[0].severity
    enabled: true
    query: analyticsRules[0].query
    queryFrequency: analyticsRules[0].queryFrequency
    queryPeriod: analyticsRules[0].queryPeriod
    triggerOperator: 'GreaterThan'
    triggerThreshold: analyticsRules[0].triggerThreshold
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: analyticsRules[0].tactics
    eventGroupingSettings: {
      aggregationKind: 'SingleAlert'
    }
  }
  dependsOn: [
    sentinelSolution
  ]
}

resource analyticsRule2 'Microsoft.SecurityInsights/alertRules@2023-02-01' = {
  scope: logAnalyticsWorkspace
  name: 'privilege-escalation-rule'
  kind: 'Scheduled'
  properties: {
    displayName: analyticsRules[1].displayName
    description: analyticsRules[1].description
    severity: analyticsRules[1].severity
    enabled: true
    query: analyticsRules[1].query
    queryFrequency: analyticsRules[1].queryFrequency
    queryPeriod: analyticsRules[1].queryPeriod
    triggerOperator: 'GreaterThan'
    triggerThreshold: analyticsRules[1].triggerThreshold
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: analyticsRules[1].tactics
    eventGroupingSettings: {
      aggregationKind: 'AlertPerResult'
    }
  }
  dependsOn: [
    sentinelSolution
  ]
}

resource analyticsRule3 'Microsoft.SecurityInsights/alertRules@2023-02-01' = {
  scope: logAnalyticsWorkspace
  name: 'suspicious-azure-activity-rule'
  kind: 'Scheduled'
  properties: {
    displayName: analyticsRules[2].displayName
    description: analyticsRules[2].description
    severity: analyticsRules[2].severity
    enabled: true
    query: analyticsRules[2].query
    queryFrequency: analyticsRules[2].queryFrequency
    queryPeriod: analyticsRules[2].queryPeriod
    triggerOperator: 'GreaterThan'
    triggerThreshold: analyticsRules[2].triggerThreshold
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: analyticsRules[2].tactics
    eventGroupingSettings: {
      aggregationKind: 'AlertPerResult'
    }
  }
  dependsOn: [
    sentinelSolution
  ]
}

// Automation Account for advanced automation scenarios
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = if (enableAutomation) {
  name: automationAccountName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Basic'
    }
    encryption: {
      keySource: 'Microsoft.Automation'
    }
    publicNetworkAccess: true
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

// Logic App for incident response automation
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = if (enableAutomation) {
  name: logicAppName
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
        'When_a_response_to_an_Azure_Sentinel_alert_is_triggered': {
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            path: '/subscribe'
          }
        }
      }
      actions: {
        'Initialize_response_variable': {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'ResponseActions'
                type: 'String'
                value: 'Incident processed automatically'
              }
            ]
          }
        }
        'Check_incident_severity': {
          type: 'Switch'
          expression: '@triggerBody()?[\'Severity\']'
          cases: {
            High: {
              case: 'High'
              actions: {
                'Send_high_severity_notification': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: '@parameters(\'notificationEndpoint\')'
                    body: {
                      text: 'High severity incident detected: @{triggerBody()?[\'Title\']}'
                      incident_id: '@{triggerBody()?[\'SystemAlertId\']}'
                      severity: '@{triggerBody()?[\'Severity\']}'
                      timestamp: '@{utcNow()}'
                    }
                  }
                }
              }
            }
            Medium: {
              case: 'Medium'
              actions: {
                'Log_medium_severity_incident': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: '@parameters(\'loggingEndpoint\')'
                    body: {
                      incident: '@{triggerBody()?[\'Title\']}'
                      severity: '@{triggerBody()?[\'Severity\']}'
                      timestamp: '@{utcNow()}'
                      action: 'logged_for_review'
                    }
                  }
                }
              }
            }
          }
          default: {
            actions: {
              'Log_standard_response': {
                type: 'Http'
                inputs: {
                  method: 'POST'
                  uri: '@parameters(\'loggingEndpoint\')'
                  body: {
                    incident: '@{triggerBody()?[\'Title\']}'
                    severity: '@{triggerBody()?[\'Severity\']}'
                    timestamp: '@{utcNow()}'
                    action: 'standard_processing'
                  }
                }
              }
            }
          }
        }
        'Update_incident_status': {
          type: 'Http'
          inputs: {
            method: 'PATCH'
            uri: 'https://management.azure.com/subscriptions/@{subscription().subscriptionId}/resourceGroups/@{resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${logAnalyticsWorkspace.name}/providers/Microsoft.SecurityInsights/incidents/@{triggerBody()?[\'SystemAlertId\']}?api-version=2023-02-01'
            headers: {
              'Authorization': 'Bearer @{variables(\'AuthToken\')}'
              'Content-Type': 'application/json'
            }
            body: {
              properties: {
                status: 'Active'
                classification: 'Undetermined'
                classificationComment: 'Automated processing initiated'
                owner: {
                  assignedTo: 'automation-system'
                  email: '@parameters(\'systemEmail\')'
                }
              }
            }
          }
        }
      }
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
        notificationEndpoint: {
          defaultValue: 'https://hooks.slack.com/services/YOUR_WEBHOOK'
          type: 'String'
        }
        loggingEndpoint: {
          defaultValue: 'https://your-logging-endpoint.com/log'
          type: 'String'
        }
        systemEmail: {
          defaultValue: notificationEmail
          type: 'String'
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/connections/azuresentinel'
            connectionName: 'azuresentinel'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azuresentinel'
          }
        }
      }
    }
  }
}

// Security Response Playbook for user account management
resource securityPlaybook 'Microsoft.Logic/workflows@2019-05-01' = if (enableAutomation) {
  name: playbookName
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
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                incidentId: {
                  type: 'string'
                }
                userPrincipalName: {
                  type: 'string'
                }
                action: {
                  type: 'string'
                }
                severity: {
                  type: 'string'
                }
              }
            }
          }
        }
      }
      actions: {
        'Parse_incident_data': {
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()'
            schema: {
              type: 'object'
              properties: {
                incidentId: {
                  type: 'string'
                }
                userPrincipalName: {
                  type: 'string'
                }
                action: {
                  type: 'string'
                }
                severity: {
                  type: 'string'
                }
              }
            }
          }
        }
        'Determine_response_action': {
          type: 'Switch'
          expression: '@body(\'Parse_incident_data\')?[\'action\']'
          cases: {
            disable_user: {
              case: 'disable_user'
              actions: {
                'Disable_user_account': {
                  type: 'Http'
                  inputs: {
                    method: 'PATCH'
                    uri: 'https://graph.microsoft.com/v1.0/users/@{body(\'Parse_incident_data\')?[\'userPrincipalName\']}'
                    headers: {
                      'Authorization': 'Bearer @{variables(\'GraphToken\')}'
                      'Content-Type': 'application/json'
                    }
                    body: {
                      accountEnabled: false
                    }
                  }
                }
                'Add_incident_comment': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://management.azure.com/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${logAnalyticsWorkspace.name}/providers/Microsoft.SecurityInsights/incidents/@{body(\'Parse_incident_data\')?[\'incidentId\']}/comments/@{guid()}?api-version=2023-02-01'
                    headers: {
                      'Authorization': 'Bearer @{variables(\'AuthToken\')}'
                      'Content-Type': 'application/json'
                    }
                    body: {
                      properties: {
                        message: 'Automated response: User account @{body(\'Parse_incident_data\')?[\'userPrincipalName\']} has been disabled due to security incident'
                      }
                    }
                  }
                }
              }
            }
            reset_password: {
              case: 'reset_password'
              actions: {
                'Force_password_reset': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://graph.microsoft.com/v1.0/users/@{body(\'Parse_incident_data\')?[\'userPrincipalName\']}/invalidateAllRefreshTokens'
                    headers: {
                      'Authorization': 'Bearer @{variables(\'GraphToken\')}'
                      'Content-Type': 'application/json'
                    }
                  }
                }
              }
            }
          }
          default: {
            actions: {
              'Log_incident_for_review': {
                type: 'Http'
                inputs: {
                  method: 'POST'
                  uri: '@parameters(\'loggingEndpoint\')'
                  body: {
                    incident: '@{body(\'Parse_incident_data\')?[\'incidentId\']}'
                    user: '@{body(\'Parse_incident_data\')?[\'userPrincipalName\']}'
                    action: 'flagged_for_manual_review'
                    timestamp: '@{utcNow()}'
                  }
                }
              }
            }
          }
        }
        'Send_completion_notification': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@parameters(\'notificationEndpoint\')'
            body: {
              text: 'Security playbook completed for incident @{body(\'Parse_incident_data\')?[\'incidentId\']}'
              user: '@{body(\'Parse_incident_data\')?[\'userPrincipalName\']}'
              action: '@{body(\'Parse_incident_data\')?[\'action\']}'
              timestamp: '@{utcNow()}'
            }
          }
        }
      }
      parameters: {
        notificationEndpoint: {
          defaultValue: 'https://hooks.slack.com/services/YOUR_WEBHOOK'
          type: 'String'
        }
        loggingEndpoint: {
          defaultValue: 'https://your-logging-endpoint.com/log'
          type: 'String'
        }
      }
    }
  }
}

// Azure Monitor Workbook for Security Operations Dashboard
resource securityWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: workbookName
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Security Operations Dashboard'
    description: 'Comprehensive security operations dashboard with incident metrics, threat trends, and response analytics'
    category: 'Security'
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '## Security Operations Overview\n\nThis dashboard provides real-time visibility into security incidents, threat trends, and response metrics across your unified security operations platform.\n\n### Key Metrics\n- **Incident Volume**: Total security incidents by severity and status\n- **Threat Detection**: Analytics rule effectiveness and alert trends\n- **Response Times**: Mean time to detection (MTTD) and mean time to response (MTTR)\n- **User Activity**: Sign-in patterns and authentication anomalies\n\n### Data Sources\n- Microsoft Sentinel\n- Azure Active Directory\n- Azure Activity Logs\n- Security Events\n'
          }
          name: 'header-text'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'SecurityIncident\n| where TimeGenerated >= ago(24h)\n| summarize Count = count() by Severity\n| order by Count desc'
            size: 1
            title: 'Incidents by Severity (24h)'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
            visualization: 'piechart'
            chartSettings: {
              seriesLabelSettings: [
                {
                  seriesName: 'High'
                  color: 'red'
                }
                {
                  seriesName: 'Medium'
                  color: 'yellow'
                }
                {
                  seriesName: 'Low'
                  color: 'green'
                }
              ]
            }
          }
          name: 'incidents-by-severity'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'SigninLogs\n| where TimeGenerated >= ago(24h)\n| where ResultType != 0\n| summarize FailedSignins = count() by bin(TimeGenerated, 1h)\n| order by TimeGenerated asc'
            size: 0
            title: 'Failed Sign-ins Trend (24h)'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
            visualization: 'timechart'
            chartSettings: {
              yAxis: [
                'FailedSignins'
              ]
            }
          }
          name: 'failed-signins-trend'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'SecurityIncident\n| where TimeGenerated >= ago(7d)\n| summarize IncidentCount = count() by Status\n| order by IncidentCount desc'
            size: 0
            title: 'Incident Status Distribution (7d)'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
            visualization: 'barchart'
          }
          name: 'incident-status-distribution'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'SecurityAlert\n| where TimeGenerated >= ago(24h)\n| summarize AlertCount = count() by AlertSeverity, bin(TimeGenerated, 1h)\n| order by TimeGenerated asc'
            size: 0
            title: 'Security Alerts Timeline (24h)'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
            visualization: 'timechart'
            chartSettings: {
              yAxis: [
                'AlertCount'
              ]
            }
          }
          name: 'security-alerts-timeline'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AuditLogs\n| where TimeGenerated >= ago(24h)\n| where OperationName has_any ("Add member to role", "Remove member from role")\n| summarize RoleChanges = count() by OperationName, bin(TimeGenerated, 1h)\n| order by TimeGenerated asc'
            size: 0
            title: 'Role Changes Activity (24h)'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
            visualization: 'timechart'
          }
          name: 'role-changes-activity'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'SecurityIncident\n| where TimeGenerated >= ago(30d)\n| where Status in ("Closed", "Resolved")\n| extend ResponseTime = datetime_diff("minute", ClosedTime, CreatedTime)\n| summarize AvgResponseTime = avg(ResponseTime), MedianResponseTime = percentile(ResponseTime, 50) by bin(TimeGenerated, 1d)\n| order by TimeGenerated asc'
            size: 0
            title: 'Incident Response Time Metrics (30d)'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
            visualization: 'timechart'
          }
          name: 'response-time-metrics'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'SigninLogs\n| where TimeGenerated >= ago(24h)\n| where ResultType == 0\n| summarize SuccessfulSignins = count() by AppDisplayName\n| top 10 by SuccessfulSignins desc'
            size: 0
            title: 'Top Applications by Successful Sign-ins (24h)'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
            visualization: 'table'
          }
          name: 'top-applications-signins'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureActivity\n| where TimeGenerated >= ago(24h)\n| where ActivityStatus == "Failed"\n| summarize FailedActivities = count() by OperationName\n| top 10 by FailedActivities desc'
            size: 0
            title: 'Top Failed Azure Activities (24h)'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
            visualization: 'table'
          }
          name: 'top-failed-activities'
        }
      ]
      fallbackResourceIds: [
        logAnalyticsWorkspace.id
      ]
    })
    sourceId: logAnalyticsWorkspace.id
  }
}

// Role assignments for managed identity
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource sentinelContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'SentinelContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ab8e14d6-4a74-4a29-9ba8-549422addade')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logAnalyticsContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'LogAnalyticsContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics workspace resource ID')
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.id

@description('Microsoft Sentinel workspace name')
output sentinelWorkspaceName string = logAnalyticsWorkspace.name

@description('Logic App name for incident response')
output logicAppName string = enableAutomation ? logicApp.name : 'Not deployed'

@description('Logic App resource ID')
output logicAppResourceId string = enableAutomation ? logicApp.id : 'Not deployed'

@description('Security playbook name')
output securityPlaybookName string = enableAutomation ? securityPlaybook.name : 'Not deployed'

@description('Security playbook resource ID')
output securityPlaybookResourceId string = enableAutomation ? securityPlaybook.id : 'Not deployed'

@description('Security workbook name')
output securityWorkbookName string = securityWorkbook.name

@description('Security workbook resource ID')
output securityWorkbookResourceId string = securityWorkbook.id

@description('Managed identity name')
output managedIdentityName string = managedIdentity.name

@description('Managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Managed identity client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Automation account name')
output automationAccountName string = enableAutomation ? automationAccount.name : 'Not deployed'

@description('Microsoft Sentinel portal URL')
output sentinelPortalUrl string = 'https://portal.azure.com/#blade/Microsoft_Azure_Security_Insights/MainMenuBlade/0/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${logAnalyticsWorkspace.name}'

@description('Unified security operations portal URL')
output unifiedSecurityPortalUrl string = 'https://security.microsoft.com'

@description('Azure Monitor Workbook URL')
output workbookUrl string = 'https://portal.azure.com/#blade/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/workbooks'

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  logAnalyticsWorkspace: logAnalyticsWorkspace.name
  sentinelEnabled: true
  uebaEnabled: enableUEBA
  automationEnabled: enableAutomation
  dataConnectorsDeployed: 3
  analyticsRulesDeployed: 3
  workbookDeployed: true
  managedIdentityDeployed: true
  keyVaultDeployed: true
}