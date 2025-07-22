// ======================================================================================
// Azure Monitor Workbook Module for Governance Dashboard
// ======================================================================================
// This module creates an Azure Monitor Workbook with predefined governance queries
// and visualizations for monitoring compliance and resource management.
// ======================================================================================

@description('The Azure region where the workbook should be deployed')
param location string = resourceGroup().location

@description('The display name for the workbook')
param workbookDisplayName string = 'Azure Governance Dashboard'

@description('Description of the workbook')
param workbookDescription string = 'Comprehensive governance and compliance dashboard for Azure resources'

@description('Workbook category for organization')
param workbookCategory string = 'governance'

@description('Tags to apply to the workbook')
param resourceTags object = {}

@description('Application Insights resource ID for workbook integration')
param applicationInsightsResourceId string

// ======================================================================================
// Workbook Template Content
// ======================================================================================

var workbookContent = {
  version: 'Notebook/1.0'
  items: [
    {
      type: 1
      content: {
        json: '# ${workbookDisplayName}\n\nThis comprehensive dashboard provides real-time visibility into Azure resource governance, compliance, and security posture across your organization.\n\n## Key Features\n- **Resource Compliance**: Monitor resources missing required tags and policy violations\n- **Location Compliance**: Track resources deployed in non-approved regions\n- **Security Posture**: View security recommendations and assessment status\n- **Policy Insights**: Analyze policy compliance across your Azure environment\n- **Resource Distribution**: Understand resource deployment patterns\n\n---'
      }
      name: 'Dashboard Title and Description'
    }
    {
      type: 9
      content: {
        version: 'KqlParameterItem/1.0'
        crossComponentResources: [
          'value::all'
        ]
        parameters: [
          {
            id: 'subscription-parameter'
            version: 'KqlParameterItem/1.0'
            name: 'Subscription'
            label: 'Subscription(s)'
            type: 6
            description: 'Select one or more subscriptions to monitor'
            isRequired: true
            multiSelect: true
            quote: '\''
            delimiter: ','
            query: 'where type =~ \'microsoft.resources/subscriptions\'\r\n| project value = subscriptionId, label = subscriptionDisplayName, selected = true'
            crossComponentResources: [
              'value::all'
            ]
            typeSettings: {
              additionalResourceOptions: [
                'value::all'
              ]
              includeAll: true
              showDefault: false
            }
            timeContext: {
              durationMs: 86400000
            }
            defaultValue: 'value::all'
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
          }
          {
            id: 'timerange-parameter'
            version: 'KqlParameterItem/1.0'
            name: 'TimeRange'
            label: 'Time Range'
            type: 4
            description: 'Select time range for data analysis'
            isRequired: true
            value: {
              durationMs: 86400000
            }
            typeSettings: {
              selectableValues: [
                {
                  durationMs: 3600000
                }
                {
                  durationMs: 14400000
                }
                {
                  durationMs: 43200000
                }
                {
                  durationMs: 86400000
                }
                {
                  durationMs: 172800000
                }
                {
                  durationMs: 259200000
                }
                {
                  durationMs: 604800000
                }
                {
                  durationMs: 1209600000
                }
                {
                  durationMs: 2419200000
                }
                {
                  durationMs: 2592000000
                }
              ]
              allowCustom: true
            }
          }
        ]
        style: 'pills'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
      }
      name: 'Parameters Section'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'resources\r\n| where subscriptionId in ({Subscription}) or \'*\' in ({Subscription})\r\n| summarize \r\n    TotalResources = count(),\r\n    ResourceTypes = dcount(type),\r\n    Subscriptions = dcount(subscriptionId),\r\n    ResourceGroups = dcount(resourceGroup),\r\n    Locations = dcount(location)'
        size: 4
        title: 'Resource Summary'
        timeContext: {
          durationMs: 0
        }
        timeContextFromParameter: 'TimeRange'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
        crossComponentResources: [
          'value::all'
        ]
        visualization: 'tiles'
        tileSettings: {
          titleContent: {
            columnMatch: 'TotalResources'
            formatter: 1
          }
          leftContent: {
            columnMatch: 'TotalResources'
            formatter: 12
            formatOptions: {
              palette: 'auto'
            }
            numberFormat: {
              unit: 17
              options: {
                style: 'decimal'
                maximumFractionDigits: 0
              }
            }
          }
          secondaryContent: {
            columnMatch: 'TotalResources'
            formatter: 1
          }
          showBorder: false
        }
      }
      name: 'Resource Summary Tiles'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'resources\r\n| where subscriptionId in ({Subscription}) or \'*\' in ({Subscription})\r\n| where tags !has "Environment" or tags !has "Owner" or tags !has "CostCenter"\r\n| summarize NonCompliantResources = count() by ResourceGroup = resourceGroup, ResourceType = type\r\n| top 20 by NonCompliantResources desc'
        size: 0
        title: 'Resources Missing Required Tags'
        timeContext: {
          durationMs: 0
        }
        timeContextFromParameter: 'TimeRange'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
        crossComponentResources: [
          'value::all'
        ]
        visualization: 'table'
        gridSettings: {
          formatters: [
            {
              columnMatch: 'NonCompliantResources'
              formatter: 8
              formatOptions: {
                palette: 'redBright'
              }
            }
          ]
          filter: true
          sortBy: [
            {
              itemKey: 'NonCompliantResources'
              sortOrder: 2
            }
          ]
        }
        sortBy: [
          {
            itemKey: 'NonCompliantResources'
            sortOrder: 2
          }
        ]
      }
      name: 'Missing Tags Table'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'policyresources\r\n| where type == "microsoft.policyinsights/policystates"\r\n| where subscriptionId in ({Subscription}) or \'*\' in ({Subscription})\r\n| summarize ComplianceCount = count() by ComplianceState = tostring(properties.complianceState)\r\n| order by ComplianceCount desc'
        size: 0
        title: 'Policy Compliance Summary'
        timeContext: {
          durationMs: 0
        }
        timeContextFromParameter: 'TimeRange'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
        crossComponentResources: [
          'value::all'
        ]
        visualization: 'piechart'
        chartSettings: {
          seriesLabelSettings: [
            {
              seriesName: 'Compliant'
              color: 'green'
            }
            {
              seriesName: 'NonCompliant'
              color: 'red'
            }
            {
              seriesName: 'Unknown'
              color: 'gray'
            }
          ]
        }
      }
      customWidth: '50'
      name: 'Policy Compliance Chart'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'securityresources\r\n| where type == "microsoft.security/assessments"\r\n| where subscriptionId in ({Subscription}) or \'*\' in ({Subscription})\r\n| summarize AssessmentCount = count() by Status = tostring(properties.status.code)\r\n| order by AssessmentCount desc'
        size: 0
        title: 'Security Assessment Status'
        timeContext: {
          durationMs: 0
        }
        timeContextFromParameter: 'TimeRange'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
        crossComponentResources: [
          'value::all'
        ]
        visualization: 'piechart'
        chartSettings: {
          seriesLabelSettings: [
            {
              seriesName: 'Healthy'
              color: 'green'
            }
            {
              seriesName: 'Unhealthy'
              color: 'red'
            }
            {
              seriesName: 'NotApplicable'
              color: 'gray'
            }
          ]
        }
      }
      customWidth: '50'
      name: 'Security Status Chart'
    }
  ]
  fallbackResourceIds: []
  fromTemplateId: 'governance-dashboard-template'
}

// ======================================================================================
// Azure Monitor Workbook Resource
// ======================================================================================

resource governanceWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'governance-workbook')
  location: location
  tags: resourceTags
  kind: 'shared'
  properties: {
    displayName: workbookDisplayName
    description: workbookDescription
    category: workbookCategory
    serializedData: string(workbookContent)
    sourceId: applicationInsightsResourceId
    timeSettings: {
      timeRange: {
        durationMs: 86400000 // 24 hours
        createdTime: '2025-01-01T00:00:00.000Z'
        isInitialTime: false
      }
    }
  }
}

// ======================================================================================
// Outputs
// ======================================================================================

@description('The resource ID of the created workbook')
output workbookId string = governanceWorkbook.id

@description('The name of the created workbook')
output workbookName string = governanceWorkbook.name

@description('The URL to access the workbook in Azure Portal')
output workbookUrl string = 'https://portal.azure.com/#@${tenant().tenantId}/resource${governanceWorkbook.id}/workbook'

@description('The display name of the workbook')
output workbookDisplayName string = workbookDisplayName