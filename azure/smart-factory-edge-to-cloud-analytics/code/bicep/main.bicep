@description('Main Bicep template for Smart Factory Edge-to-Cloud Analytics with IoT Operations and Event Hubs')
@description('This template deploys the complete manufacturing analytics infrastructure including Event Hubs, Stream Analytics, Log Analytics, and monitoring components')

// ========================================================================================
// PARAMETERS
// ========================================================================================

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Tags to apply to all resources')
param tags object = {
  solution: 'manufacturing-analytics'
  environment: environment
  deployment: 'bicep'
  purpose: 'iot-operations-eventhubs'
}

// Event Hubs Configuration
@description('Event Hubs namespace SKU')
@allowed(['Standard', 'Premium'])
param eventHubsSkuName string = 'Standard'

@description('Event Hubs throughput units (1-20 for Standard, 1-10 for Premium)')
@minValue(1)
@maxValue(20)
param eventHubsThroughputUnits int = 2

@description('Enable auto-inflate for Event Hubs namespace')
param enableAutoInflate bool = true

@description('Maximum throughput units for auto-inflate')
@minValue(1)
@maxValue(20)
param maximumThroughputUnits int = 10

@description('Number of partitions for the telemetry event hub')
@minValue(2)
@maxValue(32)
param telemetryPartitionCount int = 4

@description('Message retention days for telemetry event hub')
@minValue(1)
@maxValue(7)
param messageRetentionDays int = 3

// Stream Analytics Configuration
@description('Stream Analytics job SKU')
@allowed(['Standard'])
param streamAnalyticsSkuName string = 'Standard'

@description('Stream Analytics streaming units')
@minValue(1)
@maxValue(120)
param streamingUnits int = 3

// Log Analytics Configuration
@description('Log Analytics workspace SKU')
@allowed(['PerGB2018', 'CapacityReservation'])
param logAnalyticsSkuName string = 'PerGB2018'

@description('Log Analytics data retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 90

// Alert Configuration
@description('Email address for manufacturing alerts')
param alertEmailAddress string

@description('SMS phone number for critical alerts (format: +1234567890)')
param alertPhoneNumber string = ''

@description('Enable SMS alerts for critical conditions')
param enableSmsAlerts bool = false

// ========================================================================================
// VARIABLES
// ========================================================================================

var resourcePrefix = 'manufacturing-${environment}'
var eventHubsNamespaceName = '${resourcePrefix}-eh-${uniqueSuffix}'
var telemetryEventHubName = 'telemetry-hub'
var streamAnalyticsJobName = '${resourcePrefix}-sa-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-law-${uniqueSuffix}'
var actionGroupName = '${resourcePrefix}-alerts-${uniqueSuffix}'
var applicationInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'

// Shared access policy names
var iotOperationsPolicyName = 'IoTOperationsPolicy'
var streamAnalyticsPolicyName = 'StreamAnalyticsPolicy'

// ========================================================================================
// EXISTING RESOURCES
// ========================================================================================

// Reference to the resource group for tagging
resource resourceGroup_ref 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: resourceGroup().name
}

// ========================================================================================
// LOG ANALYTICS WORKSPACE
// ========================================================================================

@description('Log Analytics workspace for manufacturing telemetry and monitoring')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
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
      dailyQuotaGb: 10
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ========================================================================================
// APPLICATION INSIGHTS
// ========================================================================================

@description('Application Insights for manufacturing application monitoring')
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
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

// ========================================================================================
// EVENT HUBS NAMESPACE
// ========================================================================================

@description('Event Hubs namespace for manufacturing telemetry ingestion')
resource eventHubsNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: eventHubsNamespaceName
  location: location
  tags: tags
  sku: {
    name: eventHubsSkuName
    tier: eventHubsSkuName
    capacity: eventHubsThroughputUnits
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: environment == 'prod' ? true : false
    isAutoInflateEnabled: enableAutoInflate
    maximumThroughputUnits: enableAutoInflate ? maximumThroughputUnits : eventHubsThroughputUnits
    kafkaEnabled: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ========================================================================================
// EVENT HUB FOR TELEMETRY
// ========================================================================================

@description('Event Hub for manufacturing telemetry data')
resource telemetryEventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubsNamespace
  name: telemetryEventHubName
  properties: {
    messageRetentionInDays: messageRetentionDays
    partitionCount: telemetryPartitionCount
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// ========================================================================================
// EVENT HUB ACCESS POLICIES
// ========================================================================================

@description('Shared access policy for IoT Operations to send telemetry')
resource iotOperationsAccessPolicy 'Microsoft.EventHub/namespaces/eventhubs/authorizationrules@2024-01-01' = {
  parent: telemetryEventHub
  name: iotOperationsPolicyName
  properties: {
    rights: [
      'Send'
      'Listen'
    ]
  }
}

@description('Shared access policy for Stream Analytics to consume telemetry')
resource streamAnalyticsAccessPolicy 'Microsoft.EventHub/namespaces/eventhubs/authorizationrules@2024-01-01' = {
  parent: telemetryEventHub
  name: streamAnalyticsPolicyName
  properties: {
    rights: [
      'Listen'
    ]
  }
}

// ========================================================================================
// STORAGE ACCOUNT FOR STREAM ANALYTICS
// ========================================================================================

@description('Storage account for Stream Analytics job state and outputs')
resource streamAnalyticsStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'sa${resourcePrefix}${uniqueSuffix}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
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
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Container for Stream Analytics outputs
resource streamAnalyticsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${streamAnalyticsStorage.name}/default/manufacturing-analytics'
  properties: {
    publicAccess: 'None'
  }
}

// ========================================================================================
// STREAM ANALYTICS JOB
// ========================================================================================

@description('Stream Analytics job for real-time manufacturing analytics')
resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: streamAnalyticsJobName
  location: location
  tags: tags
  properties: {
    sku: {
      name: streamAnalyticsSkuName
    }
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderPolicy: 'Adjust'
    eventsOutOfOrderMaxDelayInSeconds: 5
    eventsLateArrivalMaxDelayInSeconds: 10
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    contentStoragePolicy: 'SystemAccount'
    jobType: 'Cloud'
    transformation: {
      name: 'manufacturingAnalytics'
      properties: {
        streamingUnits: streamingUnits
        query: '''
-- Equipment Anomaly Detection and OEE Calculation for Manufacturing Analytics
WITH AnomalyDetection AS (
    SELECT
        deviceId,
        System.Timestamp() AS processingTime,
        temperature,
        vibration,
        pressure,
        operationalStatus,
        productionCount,
        qualityScore,
        energyConsumption,
        CASE 
            WHEN temperature > 90 OR vibration > 1.0 OR pressure > 180 THEN 'CRITICAL'
            WHEN temperature > 80 OR vibration > 0.8 OR pressure > 170 THEN 'WARNING'
            ELSE 'NORMAL'
        END AS alertLevel
    FROM ManufacturingTelemetryInput
    WHERE operationalStatus IS NOT NULL
),

-- Operational Equipment Effectiveness (OEE) Calculation
OEEMetrics AS (
    SELECT
        deviceId,
        System.Timestamp() AS windowEnd,
        AVG(CAST(productionCount AS float)) AS avgProduction,
        AVG(CAST(qualityScore AS float)) * 100 AS avgQualityPercent,
        AVG(CAST(energyConsumption AS float)) AS avgEnergyConsumption,
        COUNT(*) AS totalReadings,
        SUM(CASE WHEN operationalStatus = 'running' THEN 1 ELSE 0 END) AS runningReadings,
        AVG(CAST(temperature AS float)) AS avgTemperature,
        AVG(CAST(vibration AS float)) AS avgVibration,
        AVG(CAST(pressure AS float)) AS avgPressure
    FROM ManufacturingTelemetryInput
    WHERE deviceId IS NOT NULL
    GROUP BY deviceId, TumblingWindow(minute, 5)
),

-- Equipment Performance Summary
PerformanceSummary AS (
    SELECT
        deviceId,
        windowEnd,
        avgProduction,
        avgQualityPercent,
        avgEnergyConsumption,
        avgTemperature,
        avgVibration,
        avgPressure,
        (CAST(runningReadings AS float) / CAST(totalReadings AS float)) * 100 AS availabilityPercent,
        -- OEE Score calculation (Availability * Quality * Performance)
        (avgProduction / 150.0) * (avgQualityPercent / 100.0) * ((CAST(runningReadings AS float) / CAST(totalReadings AS float))) * 100 AS oeeScore
    FROM OEEMetrics
    WHERE totalReadings > 0
)

-- Output critical alerts to Log Analytics
SELECT
    deviceId,
    processingTime,
    alertLevel,
    temperature,
    vibration,
    pressure,
    operationalStatus,
    'Equipment requires immediate attention - ' + alertLevel + ' condition detected' AS alertMessage,
    'manufacturing-alert' AS eventType
INTO LogAnalyticsOutput
FROM AnomalyDetection
WHERE alertLevel IN ('CRITICAL', 'WARNING');

-- Output OEE metrics and performance data to Log Analytics
SELECT
    deviceId,
    windowEnd,
    avgProduction,
    avgQualityPercent,
    avgEnergyConsumption,
    avgTemperature,
    avgVibration,
    avgPressure,
    availabilityPercent,
    oeeScore,
    CASE
        WHEN oeeScore >= 85 THEN 'Excellent'
        WHEN oeeScore >= 70 THEN 'Good'
        WHEN oeeScore >= 60 THEN 'Fair'
        ELSE 'Poor'
    END AS performanceRating,
    'manufacturing-oee' AS eventType
INTO LogAnalyticsOutput
FROM PerformanceSummary;

-- Output raw telemetry for historical analysis
SELECT
    deviceId,
    System.Timestamp() AS processingTime,
    temperature,
    vibration,
    pressure,
    operationalStatus,
    productionCount,
    qualityScore,
    energyConsumption,
    'manufacturing-telemetry' AS eventType
INTO LogAnalyticsOutput
FROM ManufacturingTelemetryInput;
'''
      }
    }
    inputs: [
      {
        name: 'ManufacturingTelemetryInput'
        properties: {
          type: 'Stream'
          datasource: {
            type: 'Microsoft.ServiceBus/EventHub'
            properties: {
              eventHubName: telemetryEventHubName
              serviceBusNamespace: eventHubsNamespaceName
              sharedAccessPolicyName: streamAnalyticsPolicyName
              sharedAccessPolicyKey: streamAnalyticsAccessPolicy.listKeys().primaryKey
              authenticationMode: 'ConnectionString'
              partitionKey: 'deviceId'
            }
          }
          compression: {
            type: 'None'
          }
          serialization: {
            type: 'Json'
            properties: {
              encoding: 'UTF8'
            }
          }
        }
      }
    ]
    outputs: [
      {
        name: 'LogAnalyticsOutput'
        properties: {
          datasource: {
            type: 'Microsoft.OperationalInsights/workspaces'
            properties: {
              workspaceId: logAnalyticsWorkspace.properties.customerId
              sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
            }
          }
          serialization: {
            type: 'Json'
            properties: {
              encoding: 'UTF8'
              format: 'LineSeparated'
            }
          }
        }
      }
    ]
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ========================================================================================
// ACTION GROUPS FOR ALERTS
// ========================================================================================

@description('Action group for manufacturing maintenance team notifications')
resource maintenanceActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'MaintTeam'
    enabled: true
    emailReceivers: [
      {
        name: 'MaintenanceManager'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: enableSmsAlerts && !empty(alertPhoneNumber) ? [
      {
        name: 'ShiftSupervisor'
        countryCode: '1'
        phoneNumber: replace(alertPhoneNumber, '+1', '')
      }
    ] : []
    webhookReceivers: []
    azureFunctionReceivers: []
    logicAppReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    armRoleReceivers: []
    eventHubReceivers: []
  }
}

// ========================================================================================
// ALERT RULES
// ========================================================================================

@description('Alert rule for high telemetry ingestion rate indicating potential issues')
resource highIngestionAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${resourcePrefix}-high-ingestion-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when manufacturing telemetry ingestion rate is unusually high'
    severity: 2
    enabled: true
    scopes: [
      eventHubsNamespace.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighIngestionRate'
          metricName: 'IncomingMessages'
          metricNamespace: 'Microsoft.EventHub/namespaces'
          operator: 'GreaterThan'
          threshold: 1000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: maintenanceActionGroup.id
      }
    ]
  }
}

@description('Alert rule for Stream Analytics job failures')
resource streamAnalyticsFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${resourcePrefix}-stream-analytics-failure'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Stream Analytics job experiences runtime errors'
    severity: 1
    enabled: true
    scopes: [
      streamAnalyticsJob.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'RuntimeErrors'
          metricName: 'Errors'
          metricNamespace: 'Microsoft.StreamAnalytics/streamingjobs'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: maintenanceActionGroup.id
      }
    ]
  }
}

// ========================================================================================
// RBAC ASSIGNMENTS
// ========================================================================================

// Grant Stream Analytics job access to Event Hubs
resource eventHubsDataReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(streamAnalyticsJob.id, eventHubsNamespace.id, 'EventHubsDataReceiver')
  scope: eventHubsNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Receiver
    principalId: streamAnalyticsJob.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Stream Analytics job access to Log Analytics
resource logAnalyticsContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(streamAnalyticsJob.id, logAnalyticsWorkspace.id, 'LogAnalyticsContributor')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293') // Log Analytics Contributor
    principalId: streamAnalyticsJob.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ========================================================================================
// DIAGNOSTIC SETTINGS
// ========================================================================================

@description('Diagnostic settings for Event Hubs namespace')
resource eventHubsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'manufacturing-eventhubs-diagnostics'
  scope: eventHubsNamespace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

@description('Diagnostic settings for Stream Analytics job')
resource streamAnalyticsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'manufacturing-streamanalytics-diagnostics'
  scope: streamAnalyticsJob
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// ========================================================================================
// OUTPUTS
// ========================================================================================

@description('Event Hubs namespace name')
output eventHubsNamespaceName string = eventHubsNamespace.name

@description('Event Hubs namespace connection string for IoT Operations')
output iotOperationsConnectionString string = iotOperationsAccessPolicy.listKeys().primaryConnectionString

@description('Event Hubs namespace connection string for Stream Analytics')
output streamAnalyticsConnectionString string = streamAnalyticsAccessPolicy.listKeys().primaryConnectionString

@description('Telemetry Event Hub name')
output telemetryEventHubName string = telemetryEventHub.name

@description('Stream Analytics job name')
output streamAnalyticsJobName string = streamAnalyticsJob.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Action group resource ID for alerts')
output actionGroupId string = maintenanceActionGroup.id

@description('Storage account name for Stream Analytics')
output storageAccountName string = streamAnalyticsStorage.name

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Event Hubs namespace resource ID')
output eventHubsNamespaceResourceId string = eventHubsNamespace.id

@description('Stream Analytics job resource ID')
output streamAnalyticsJobResourceId string = streamAnalyticsJob.id

@description('Deployment summary with key endpoints and connection information')
output deploymentSummary object = {
  eventHubsNamespace: eventHubsNamespace.name
  telemetryEventHub: telemetryEventHub.name
  streamAnalyticsJob: streamAnalyticsJob.name
  logAnalyticsWorkspace: logAnalyticsWorkspace.name
  applicationInsights: applicationInsights.name
  resourceGroup: resourceGroup().name
  region: location
  environment: environment
}