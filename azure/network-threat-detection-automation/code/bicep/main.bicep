// ============================================================================
// Main Bicep template for Automated Network Threat Detection
// Deploys Azure Network Watcher, Log Analytics, and Logic Apps for threat detection
// ============================================================================

targetScope = 'resourceGroup'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Log Analytics workspace retention in days')
@minValue(7)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Log Analytics workspace pricing tier')
@allowed(['PerGB2018', 'PerNode', 'Premium', 'Standard', 'Standalone', 'Unlimited', 'CapacityReservation'])
param logAnalyticsPricingTier string = 'PerGB2018'

@description('NSG Flow Logs retention in days')
@minValue(1)
@maxValue(365)
param flowLogsRetentionDays int = 7

@description('Email address for security notifications')
param securityNotificationEmail string

@description('ServiceNow instance URL for incident creation (optional)')
param serviceNowInstanceUrl string = ''

@description('Enable Network Watcher if not already enabled')
param enableNetworkWatcher bool = true

@description('Existing Network Security Group resource ID for flow logs')
param existingNsgResourceId string = ''

@description('Tags to be applied to all resources')
param tags object = {
  purpose: 'network-security'
  environment: environment
  'last-updated': utcNow('yyyy-MM-dd')
}

// ============================================================================
// Variables
// ============================================================================

var storageAccountName = 'sanetworklogs${resourceSuffix}'
var logAnalyticsWorkspaceName = 'law-threat-detection-${resourceSuffix}'
var logicAppName = 'la-threat-response-${resourceSuffix}'
var networkWatcherName = 'NetworkWatcher_${location}'
var flowLogName = 'fl-${resourceSuffix}'
var workbookName = 'Network-Threat-Detection-Dashboard'

// Alert rule names
var portScanningAlertName = 'Port-Scanning-Alert'
var dataExfiltrationAlertName = 'Data-Exfiltration-Alert'
var externalFailedConnectionsAlertName = 'External-Failed-Connections-Alert'

// ============================================================================
// Network Watcher (if needed)
// ============================================================================

resource networkWatcher 'Microsoft.Network/networkWatchers@2023-09-01' = if (enableNetworkWatcher) {
  name: networkWatcherName
  location: location
  tags: tags
  properties: {}
}

// ============================================================================
// Storage Account for NSG Flow Logs
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Allow'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// ============================================================================
// Log Analytics Workspace
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsPricingTier
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// NSG Flow Logs Configuration
// ============================================================================

resource flowLogConfig 'Microsoft.Network/networkWatchers/flowLogs@2023-09-01' = {
  name: flowLogName
  parent: enableNetworkWatcher ? networkWatcher : null
  location: location
  tags: tags
  properties: {
    targetResourceId: !empty(existingNsgResourceId) ? existingNsgResourceId : ''
    storageId: storageAccount.id
    enabled: true
    format: {
      type: 'JSON'
      version: 2
    }
    retentionPolicy: {
      days: flowLogsRetentionDays
      enabled: true
    }
    flowAnalyticsConfiguration: {
      networkWatcherFlowAnalyticsConfiguration: {
        enabled: true
        workspaceResourceId: logAnalyticsWorkspace.id
        trafficAnalyticsInterval: 10
      }
    }
  }
}

// ============================================================================
// Alert Rules for Threat Detection
// ============================================================================

// Port Scanning Alert Rule
resource portScanningAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: portScanningAlertName
  location: location
  tags: tags
  properties: {
    displayName: 'Port Scanning Detection Alert'
    description: 'Detects suspicious port scanning activity from external sources'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    windowSize: 'PT1H'
    criteria: {
      allOf: [
        {
          query: '''
            AzureNetworkAnalytics_CL
            | where TimeGenerated > ago(1h)
            | where FlowStatus_s == "D"
            | summarize DestPorts = dcount(DestPort_d), FlowCount = count() by SrcIP_s, bin(TimeGenerated, 5m)
            | where DestPorts > 20 and FlowCount > 50
            | project TimeGenerated, SrcIP_s, DestPorts, FlowCount, ThreatLevel = "High"
          '''
          timeAggregation: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: []
      customProperties: {}
    }
  }
}

// Data Exfiltration Alert Rule
resource dataExfiltrationAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: dataExfiltrationAlertName
  location: location
  tags: tags
  properties: {
    displayName: 'Data Exfiltration Detection Alert'
    description: 'Detects potential data exfiltration based on unusual outbound data transfer volumes'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT10M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    windowSize: 'PT1H'
    criteria: {
      allOf: [
        {
          query: '''
            AzureNetworkAnalytics_CL
            | where TimeGenerated > ago(1h)
            | where FlowStatus_s == "A"
            | summarize TotalBytes = sum(OutboundBytes_d) by SrcIP_s, DestIP_s, bin(TimeGenerated, 10m)
            | where TotalBytes > 1000000000
            | project TimeGenerated, SrcIP_s, DestIP_s, TotalBytes, ThreatLevel = "Medium"
          '''
          timeAggregation: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: []
      customProperties: {}
    }
  }
}

// External Failed Connections Alert Rule
resource externalFailedConnectionsAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: externalFailedConnectionsAlertName
  location: location
  tags: tags
  properties: {
    displayName: 'External Failed Connections Alert'
    description: 'Detects high volume of failed connection attempts from external IPs'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    windowSize: 'PT1H'
    criteria: {
      allOf: [
        {
          query: '''
            AzureNetworkAnalytics_CL
            | where TimeGenerated > ago(1h)
            | where FlowStatus_s == "D" and FlowType_s == "ExternalPublic"
            | summarize FailedAttempts = count() by SrcIP_s, DestIP_s, bin(TimeGenerated, 5m)
            | where FailedAttempts > 100
            | project TimeGenerated, SrcIP_s, DestIP_s, FailedAttempts, ThreatLevel = "High"
          '''
          timeAggregation: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: []
      customProperties: {}
    }
  }
}

// ============================================================================
// Logic Apps for Automated Response
// ============================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        securityEmail: {
          type: 'string'
          defaultValue: securityNotificationEmail
        }
        serviceNowUrl: {
          type: 'string'
          defaultValue: serviceNowInstanceUrl
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                schemaId: {
                  type: 'string'
                }
                data: {
                  type: 'object'
                }
              }
            }
          }
        }
      }
      actions: {
        'Parse_Alert_Data': {
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()?[\'data\']'
            schema: {
              type: 'object'
              properties: {
                alertRule: {
                  type: 'string'
                }
                severity: {
                  type: 'string'
                }
                description: {
                  type: 'string'
                }
              }
            }
          }
        }
        'Send_Email_Notification': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://graph.microsoft.com/v1.0/me/sendMail'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              message: {
                subject: 'Network Threat Detected - @{body(\'Parse_Alert_Data\')?[\'alertRule\']}'
                body: {
                  contentType: 'HTML'
                  content: 'A network threat has been detected by Azure Network Watcher monitoring. Alert: @{body(\'Parse_Alert_Data\')?[\'alertRule\']} Severity: @{body(\'Parse_Alert_Data\')?[\'severity\']} Description: @{body(\'Parse_Alert_Data\')?[\'description\']} Please review the alert details and take appropriate action.'
                }
                toRecipients: [
                  {
                    emailAddress: {
                      address: '@parameters(\'securityEmail\')'
                    }
                  }
                ]
              }
            }
          }
          runAfter: {
            'Parse_Alert_Data': [
              'Succeeded'
            ]
          }
        }
        'Create_ServiceNow_Incident': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@{parameters(\'serviceNowUrl\')}/api/now/table/incident'
            headers: {
              'Content-Type': 'application/json'
              'Accept': 'application/json'
            }
            body: {
              short_description: 'Network threat detected by Azure monitoring - @{body(\'Parse_Alert_Data\')?[\'alertRule\']}'
              description: 'Automated incident created from Azure Network Watcher threat detection. Alert: @{body(\'Parse_Alert_Data\')?[\'alertRule\']} Severity: @{body(\'Parse_Alert_Data\')?[\'severity\']}'
              urgency: '2'
              priority: '2'
              category: 'Security'
              subcategory: 'Network Security'
            }
          }
          runAfter: {
            'Send_Email_Notification': [
              'Succeeded'
            ]
          }
        }
      }
    }
  }
}

// ============================================================================
// Workbook for Threat Monitoring Dashboard
// ============================================================================

resource threatMonitoringWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, workbookName)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: workbookName
    serializedData: '''
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Network Threat Detection Dashboard\\n\\nThis dashboard provides real-time monitoring of network security threats detected by Azure Network Watcher and Log Analytics.\\n\\n> **Note**: This dashboard requires NSG Flow Logs to be enabled and data to be flowing to Log Analytics."
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureNetworkAnalytics_CL\\n| where TimeGenerated > ago(24h)\\n| where FlowStatus_s == \\"D\\"\\n| summarize DeniedFlows = count() by bin(TimeGenerated, 1h)\\n| render timechart",
        "size": 0,
        "title": "Denied Network Flows (24h)",
        "timeContext": {
          "durationMs": 86400000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": "timechart"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureNetworkAnalytics_CL\\n| where TimeGenerated > ago(24h)\\n| where FlowStatus_s == \\"D\\"\\n| summarize ThreatCount = count() by SrcIP_s\\n| top 10 by ThreatCount desc\\n| render piechart",
        "size": 0,
        "title": "Top Threat Source IPs",
        "timeContext": {
          "durationMs": 86400000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": "piechart"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureNetworkAnalytics_CL\\n| where TimeGenerated > ago(1h)\\n| where FlowStatus_s == \\"A\\"\\n| summarize TotalBytes = sum(OutboundBytes_d) by SrcIP_s, DestIP_s\\n| where TotalBytes > 100000000\\n| project SrcIP_s, DestIP_s, TotalBytes_MB = TotalBytes / 1024 / 1024\\n| order by TotalBytes_MB desc\\n| take 20",
        "size": 0,
        "title": "High Volume Data Transfers (Last Hour)",
        "timeContext": {
          "durationMs": 3600000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": "table"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureNetworkAnalytics_CL\\n| where TimeGenerated > ago(1h)\\n| where FlowStatus_s == \\"D\\"\\n| summarize DestPorts = dcount(DestPort_d), FlowCount = count() by SrcIP_s\\n| where DestPorts > 10 and FlowCount > 20\\n| project SrcIP_s, DestPorts, FlowCount, ThreatLevel = \\"Potential Port Scan\\"\\n| order by DestPorts desc, FlowCount desc",
        "size": 0,
        "title": "Potential Port Scanning Activity",
        "timeContext": {
          "durationMs": 3600000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": "table"
      }
    }
  ]
}
'''
    category: 'workbook'
    sourceId: logAnalyticsWorkspace.id
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The resource ID of the created Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The workspace ID (customer ID) of the Log Analytics workspace')
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('The name of the created storage account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the created storage account')
output storageAccountId string = storageAccount.id

@description('The name of the created Logic App')
output logicAppName string = logicApp.name

@description('The resource ID of the created Logic App')
output logicAppId string = logicApp.id

@description('The callback URL for the Logic App trigger')
output logicAppCallbackUrl string = '${logicApp.properties.accessEndpoint}/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=${listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicAppName, 'manual'), '2019-05-01').queries.sig}'

@description('The name of the created Network Watcher')
output networkWatcherName string = enableNetworkWatcher ? networkWatcher.name : 'Not created'

@description('The name of the created flow log configuration')
output flowLogName string = flowLogConfig.name

@description('The names of the created alert rules')
output alertRuleNames array = [
  portScanningAlert.name
  dataExfiltrationAlert.name
  externalFailedConnectionsAlert.name
]

@description('The resource ID of the created workbook')
output workbookId string = threatMonitoringWorkbook.id

@description('Post-deployment configuration steps')
output postDeploymentInstructions object = {
  step1: 'Configure Network Security Group resource ID in flow log configuration if not provided during deployment'
  step2: 'Set up authentication for Logic App email and ServiceNow integrations'
  step3: 'Configure alert action groups to trigger Logic App workflow'
  step4: 'Review and customize threat detection queries in Log Analytics'
  step5: 'Test alert rules and automated response workflows'
  step6: 'Configure workbook permissions for security team access'
}