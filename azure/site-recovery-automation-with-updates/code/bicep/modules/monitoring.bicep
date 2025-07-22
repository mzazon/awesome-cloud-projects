@description('Monitoring and alerting module for disaster recovery')

// Parameters
@description('Location for monitoring resources')
param location string

@description('Action Group name')
param actionGroupName string

@description('Admin email for alerts')
param adminEmail string

@description('Log Analytics Workspace name')
param logAnalyticsWorkspaceName string

@description('Primary VM resource ID')
param primaryVmResourceId string

@description('Resource tags')
param tags object

// Action Group for disaster recovery alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'DR-Alerts'
    enabled: true
    emailReceivers: [
      {
        name: 'admin'
        emailAddress: adminEmail
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

// High CPU usage alert
resource highCpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-cpu-${uniqueString(primaryVmResourceId)}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when CPU usage exceeds 80%'
    severity: 2
    enabled: true
    scopes: [
      primaryVmResourceId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// VM availability alert
resource vmAvailabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-vm-availability-${uniqueString(primaryVmResourceId)}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when VM is not available'
    severity: 1
    enabled: true
    scopes: [
      primaryVmResourceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'VMAvailability'
          metricName: 'VmAvailabilityMetric'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Disk usage alert
resource diskUsageAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-disk-usage-${uniqueString(primaryVmResourceId)}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when disk usage exceeds 90%'
    severity: 2
    enabled: true
    scopes: [
      primaryVmResourceId
    ]
    evaluationFrequency: 'PT15M'
    windowSize: 'PT30M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighDiskUsage'
          metricName: 'OS Disk Used Percent'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 90
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Activity Log Alert for VM operations
resource vmOperationAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-vm-operations-${uniqueString(primaryVmResourceId)}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert for critical VM operations'
    enabled: true
    scopes: [
      primaryVmResourceId
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Compute/virtualMachines/deallocate/action'
        }
        {
          field: 'level'
          equals: 'Critical'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

// Workbook for disaster recovery dashboard
resource drWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid('dr-workbook-${uniqueString(resourceGroup().id)}')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Disaster Recovery Dashboard'
    description: 'Comprehensive dashboard for disaster recovery monitoring'
    serializedData: '''{
      "version": "Notebook/1.0",
      "items": [
        {
          "type": 1,
          "content": {
            "json": "# Disaster Recovery Dashboard\\n\\nThis dashboard provides comprehensive monitoring for your disaster recovery solution."
          },
          "name": "text - 0"
        },
        {
          "type": 10,
          "content": {
            "chartId": "workbook-vm-metrics",
            "version": "MetricsItem/2.0",
            "size": 0,
            "chartType": 2,
            "resourceIds": [
              "${primaryVmResourceId}"
            ],
            "timeContext": {
              "durationMs": 3600000
            },
            "metrics": [
              {
                "namespace": "Microsoft.Compute/virtualMachines",
                "metric": "Microsoft.Compute/virtualMachines--Percentage CPU",
                "aggregation": 4,
                "splitBy": null
              }
            ],
            "title": "VM CPU Usage",
            "gridSettings": {
              "rowLimit": 10000
            }
          },
          "name": "vm-cpu-metrics"
        }
      ],
      "isLocked": false,
      "fallbackResourceIds": [
        "${primaryVmResourceId}"
      ]
    }'''
    category: 'workbook'
    sourceId: logAnalyticsWorkspaceName
  }
}

// Outputs
@description('Action Group ID')
output actionGroupId string = actionGroup.id

@description('Action Group name')
output actionGroupName string = actionGroup.name

@description('High CPU alert ID')
output highCpuAlertId string = highCpuAlert.id

@description('VM availability alert ID')
output vmAvailabilityAlertId string = vmAvailabilityAlert.id

@description('Disk usage alert ID')
output diskUsageAlertId string = diskUsageAlert.id

@description('VM operation alert ID')
output vmOperationAlertId string = vmOperationAlert.id

@description('DR Workbook ID')
output drWorkbookId string = drWorkbook.id