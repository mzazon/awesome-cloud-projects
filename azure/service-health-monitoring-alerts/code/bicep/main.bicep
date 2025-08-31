@description('Location for all resources')
param location string = resourceGroup().location

@description('Email address for notifications')
param notificationEmail string

@description('Phone number for SMS notifications (format: +1234567890)')
param notificationPhone string = ''

@description('Resource tags to apply to all resources')
param tags object = {
  purpose: 'service-health-monitoring'
  environment: 'production'
}

@description('Action group short name (max 12 characters)')
@maxLength(12)
param actionGroupShortName string = 'SvcHealth'

@description('Subscription ID for alert scope (defaults to current subscription)')
param subscriptionId string = subscription().subscriptionId

// Generate unique suffix for resource names
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var actionGroupName = 'ag-service-health-${uniqueSuffix}'

// Action Group for Service Health Notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: [
      {
        name: 'admin-email'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: !empty(notificationPhone) ? [
      {
        name: 'admin-sms'
        countryCode: '1'
        phoneNumber: replace(notificationPhone, '+1', '')
      }
    ] : []
  }
}

// Alert Rule for Service Issues
resource serviceIssueAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'ServiceIssueAlert-${uniqueSuffix}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert for Azure service issues affecting subscription'
    enabled: true
    scopes: [
      '/subscriptions/${subscriptionId}'
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          field: 'properties.incidentType'
          equals: 'Incident'
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

// Alert Rule for Planned Maintenance
resource plannedMaintenanceAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'PlannedMaintenanceAlert-${uniqueSuffix}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert for planned Azure maintenance events'
    enabled: true
    scopes: [
      '/subscriptions/${subscriptionId}'
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          field: 'properties.incidentType'
          equals: 'Maintenance'
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

// Alert Rule for Health Advisories
resource healthAdvisoryAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'HealthAdvisoryAlert-${uniqueSuffix}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert for Azure health advisories and recommendations'
    enabled: true
    scopes: [
      '/subscriptions/${subscriptionId}'
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          field: 'properties.incidentType'
          equals: 'Information'
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

// Alert Rule for Security Advisories
resource securityAdvisoryAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'SecurityAdvisoryAlert-${uniqueSuffix}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert for Azure security advisories'
    enabled: true
    scopes: [
      '/subscriptions/${subscriptionId}'
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          field: 'properties.incidentType'
          equals: 'Security'
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

// Alert Rule for Critical Services (Virtual Machines, Storage, Networking)
resource criticalServicesAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'CriticalServicesAlert-${uniqueSuffix}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert for critical Azure services: Virtual Machines, Storage, Networking'
    enabled: true
    scopes: [
      '/subscriptions/${subscriptionId}'
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          anyOf: [
            {
              field: 'properties.impactedServices[*].ServiceName'
              containsAny: [
                'Virtual Machines'
                'Storage'
                'Virtual Network'
                'Load Balancer'
                'Application Gateway'
                'Azure DNS'
              ]
            }
          ]
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

// Outputs
@description('Action Group Resource ID')
output actionGroupId string = actionGroup.id

@description('Action Group Name')
output actionGroupName string = actionGroup.name

@description('Service Issue Alert Rule ID')
output serviceIssueAlertId string = serviceIssueAlert.id

@description('Planned Maintenance Alert Rule ID')
output plannedMaintenanceAlertId string = plannedMaintenanceAlert.id

@description('Health Advisory Alert Rule ID')
output healthAdvisoryAlertId string = healthAdvisoryAlert.id

@description('Security Advisory Alert Rule ID')
output securityAdvisoryAlertId string = securityAdvisoryAlert.id

@description('Critical Services Alert Rule ID')
output criticalServicesAlertId string = criticalServicesAlert.id

@description('All Alert Rule Names')
output alertRuleNames array = [
  serviceIssueAlert.name
  plannedMaintenanceAlert.name
  healthAdvisoryAlert.name
  securityAdvisoryAlert.name
  criticalServicesAlert.name
]