@description('Logic Apps module for health monitoring orchestration')

// Parameters
@description('Name of the orchestrator Logic App')
param orchestratorName string

@description('Name of the restart handler Logic App')
param restartHandlerName string

@description('Name of the scale handler Logic App')
param scaleHandlerName string

@description('Azure region for deployment')
param location string

@description('Resource tags')
param tags object

@description('Service Bus connection string')
@secure()
param serviceBusConnectionString string

@description('Health events queue name')
param healthQueueName string

@description('Remediation actions topic name')
param remediationTopicName string

// Service Bus API Connection
resource serviceBusConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'servicebus-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Service Bus Connection'
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'servicebus')
    }
    parameterValues: {
      connectionString: serviceBusConnectionString
    }
  }
}

// Health Monitoring Orchestrator Logic App
resource orchestratorLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: orchestratorName
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-04-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_a_resource_health_alert_is_fired': {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                resourceId: {
                  type: 'string'
                }
                status: {
                  type: 'string'
                }
                eventTime: {
                  type: 'string'
                }
                resourceType: {
                  type: 'string'
                }
                description: {
                  type: 'string'
                }
                reason: {
                  type: 'string'
                }
                correlationId: {
                  type: 'string'
                }
              }
              required: [
                'resourceId'
                'status'
                'eventTime'
                'resourceType'
              ]
            }
          }
        }
      }
      actions: {
        'Initialize_Event_Data': {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'EventData'
                type: 'object'
                value: {
                  resourceId: '@triggerBody()?[\'resourceId\']'
                  status: '@triggerBody()?[\'status\']'
                  eventTime: '@triggerBody()?[\'eventTime\']'
                  resourceType: '@triggerBody()?[\'resourceType\']'
                  description: '@triggerBody()?[\'description\']'
                  reason: '@triggerBody()?[\'reason\']'
                  correlationId: '@triggerBody()?[\'correlationId\']'
                  processedTime: '@utcnow()'
                }
              }
            ]
          }
        }
        'Send_to_Health_Queue': {
          runAfter: {
            'Initialize_Event_Data': [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            body: {
              ContentData: '@base64(string(variables(\'EventData\')))'
              ContentType: 'application/json'
              Properties: {
                EventType: 'HealthAlert'
                Source: 'ResourceHealth'
                Timestamp: '@variables(\'EventData\')[\'processedTime\']'
              }
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: concat('/@{encodeURIComponent(encodeURIComponent(\'', healthQueueName, '\'))}/messages')
          }
        }
        'Determine_Remediation_Action': {
          runAfter: {
            'Send_to_Health_Queue': [
              'Succeeded'
            ]
          }
          type: 'Switch'
          expression: '@variables(\'EventData\')[\'status\']'
          cases: {
            'Unavailable': {
              case: 'Unavailable'
              actions: {
                'Send_Restart_Action': {
                  type: 'ApiConnection'
                  inputs: {
                    body: {
                      ContentData: '@base64(string(variables(\'EventData\')))'
                      ContentType: 'application/json'
                      Properties: {
                        ActionType: 'restart'
                        Priority: 'high'
                        ResourceType: '@variables(\'EventData\')[\'resourceType\']'
                      }
                    }
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    path: concat('/@{encodeURIComponent(encodeURIComponent(\'', remediationTopicName, '\'))}/messages')
                  }
                }
              }
            }
            'Degraded': {
              case: 'Degraded'
              actions: {
                'Send_Scale_Action': {
                  type: 'ApiConnection'
                  inputs: {
                    body: {
                      ContentData: '@base64(string(variables(\'EventData\')))'
                      ContentType: 'application/json'
                      Properties: {
                        ActionType: 'scale'
                        Priority: 'medium'
                        ResourceType: '@variables(\'EventData\')[\'resourceType\']'
                      }
                    }
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    path: concat('/@{encodeURIComponent(encodeURIComponent(\'', remediationTopicName, '\'))}/messages')
                  }
                }
              }
            }
            'Unknown': {
              case: 'Unknown'
              actions: {
                'Send_Investigation_Action': {
                  type: 'ApiConnection'
                  inputs: {
                    body: {
                      ContentData: '@base64(string(variables(\'EventData\')))'
                      ContentType: 'application/json'
                      Properties: {
                        ActionType: 'investigate'
                        Priority: 'low'
                        ResourceType: '@variables(\'EventData\')[\'resourceType\']'
                      }
                    }
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    path: concat('/@{encodeURIComponent(encodeURIComponent(\'', remediationTopicName, '\'))}/messages')
                  }
                }
              }
            }
          }
          default: {
            actions: {
              'Log_Unknown_Status': {
                type: 'Compose'
                inputs: {
                  message: 'Unknown health status received'
                  status: '@variables(\'EventData\')[\'status\']'
                  resourceId: '@variables(\'EventData\')[\'resourceId\']'
                }
              }
            }
          }
        }
        'Response': {
          runAfter: {
            'Determine_Remediation_Action': [
              'Succeeded'
              'Failed'
              'Skipped'
            ]
          }
          type: 'Response'
          inputs: {
            statusCode: 200
            body: {
              message: 'Health event processed successfully'
              correlationId: '@variables(\'EventData\')[\'correlationId\']'
              processedTime: '@variables(\'EventData\')[\'processedTime\']'
            }
            headers: {
              'Content-Type': 'application/json'
            }
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          servicebus: {
            connectionId: serviceBusConnection.id
            connectionName: serviceBusConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'servicebus')
          }
        }
      }
    }
  }
}

// Restart Handler Logic App
resource restartHandlerLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: restartHandlerName
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-04-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_a_restart_message_is_received': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: concat('/@{encodeURIComponent(encodeURIComponent(\'', remediationTopicName, '\'))}/subscriptions/@{encodeURIComponent(\'restart-handler\')}/messages/head')
            queries: {
              subscriptionType: 'Main'
            }
          }
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
        }
      }
      actions: {
        'Parse_Restart_Message': {
          runAfter: {}
          type: 'ParseJson'
          inputs: {
            content: '@base64ToString(triggerBody()?[\'ContentData\'])'
            schema: {
              type: 'object'
              properties: {
                resourceId: {
                  type: 'string'
                }
                status: {
                  type: 'string'
                }
                eventTime: {
                  type: 'string'
                }
                resourceType: {
                  type: 'string'
                }
                description: {
                  type: 'string'
                }
                reason: {
                  type: 'string'
                }
                correlationId: {
                  type: 'string'
                }
                processedTime: {
                  type: 'string'
                }
              }
            }
          }
        }
        'Determine_Resource_Type': {
          runAfter: {
            'Parse_Restart_Message': [
              'Succeeded'
            ]
          }
          type: 'Switch'
          expression: '@body(\'Parse_Restart_Message\')?[\'resourceType\']'
          cases: {
            'Virtual_Machine': {
              case: 'Microsoft.Compute/virtualMachines'
              actions: {
                'Restart_Virtual_Machine': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://httpbin.org/post'
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      action: 'restart_vm'
                      resourceId: '@body(\'Parse_Restart_Message\')?[\'resourceId\']'
                      timestamp: '@utcnow()'
                      correlationId: '@body(\'Parse_Restart_Message\')?[\'correlationId\']'
                    }
                  }
                }
              }
            }
            'App_Service': {
              case: 'Microsoft.Web/sites'
              actions: {
                'Restart_App_Service': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://httpbin.org/post'
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      action: 'restart_app_service'
                      resourceId: '@body(\'Parse_Restart_Message\')?[\'resourceId\']'
                      timestamp: '@utcnow()'
                      correlationId: '@body(\'Parse_Restart_Message\')?[\'correlationId\']'
                    }
                  }
                }
              }
            }
          }
          default: {
            actions: {
              'Log_Unsupported_Resource': {
                type: 'Compose'
                inputs: {
                  message: 'Unsupported resource type for restart action'
                  resourceType: '@body(\'Parse_Restart_Message\')?[\'resourceType\']'
                  resourceId: '@body(\'Parse_Restart_Message\')?[\'resourceId\']'
                }
              }
            }
          }
        }
        'Complete_Message': {
          runAfter: {
            'Determine_Resource_Type': [
              'Succeeded'
              'Failed'
              'Skipped'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'delete'
            path: concat('/@{encodeURIComponent(encodeURIComponent(\'', remediationTopicName, '\'))}/subscriptions/@{encodeURIComponent(\'restart-handler\')}/messages/complete')
            queries: {
              lockToken: '@triggerBody()?[\'LockToken\']'
              subscriptionType: 'Main'
            }
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          servicebus: {
            connectionId: serviceBusConnection.id
            connectionName: serviceBusConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'servicebus')
          }
        }
      }
    }
  }
}

// Scale Handler Logic App
resource scaleHandlerLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: scaleHandlerName
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-04-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_a_scale_message_is_received': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: concat('/@{encodeURIComponent(encodeURIComponent(\'', remediationTopicName, '\'))}/subscriptions/@{encodeURIComponent(\'auto-scale-handler\')}/messages/head')
            queries: {
              subscriptionType: 'Main'
            }
          }
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
        }
      }
      actions: {
        'Parse_Scale_Message': {
          runAfter: {}
          type: 'ParseJson'
          inputs: {
            content: '@base64ToString(triggerBody()?[\'ContentData\'])'
            schema: {
              type: 'object'
              properties: {
                resourceId: {
                  type: 'string'
                }
                status: {
                  type: 'string'
                }
                eventTime: {
                  type: 'string'
                }
                resourceType: {
                  type: 'string'
                }
                description: {
                  type: 'string'
                }
                reason: {
                  type: 'string'
                }
                correlationId: {
                  type: 'string'
                }
                processedTime: {
                  type: 'string'
                }
              }
            }
          }
        }
        'Determine_Scale_Action': {
          runAfter: {
            'Parse_Scale_Message': [
              'Succeeded'
            ]
          }
          type: 'Switch'
          expression: '@body(\'Parse_Scale_Message\')?[\'resourceType\']'
          cases: {
            'App_Service_Plan': {
              case: 'Microsoft.Web/serverfarms'
              actions: {
                'Scale_App_Service_Plan': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://httpbin.org/post'
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      action: 'scale_app_service_plan'
                      resourceId: '@body(\'Parse_Scale_Message\')?[\'resourceId\']'
                      scaleDirection: 'up'
                      scaleAmount: 1
                      timestamp: '@utcnow()'
                      correlationId: '@body(\'Parse_Scale_Message\')?[\'correlationId\']'
                    }
                  }
                }
              }
            }
            'Virtual_Machine_Scale_Set': {
              case: 'Microsoft.Compute/virtualMachineScaleSets'
              actions: {
                'Scale_VMSS': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://httpbin.org/post'
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      action: 'scale_vmss'
                      resourceId: '@body(\'Parse_Scale_Message\')?[\'resourceId\']'
                      scaleDirection: 'up'
                      scaleAmount: 2
                      timestamp: '@utcnow()'
                      correlationId: '@body(\'Parse_Scale_Message\')?[\'correlationId\']'
                    }
                  }
                }
              }
            }
          }
          default: {
            actions: {
              'Log_Unsupported_Scale_Resource': {
                type: 'Compose'
                inputs: {
                  message: 'Unsupported resource type for scale action'
                  resourceType: '@body(\'Parse_Scale_Message\')?[\'resourceType\']'
                  resourceId: '@body(\'Parse_Scale_Message\')?[\'resourceId\']'
                }
              }
            }
          }
        }
        'Complete_Scale_Message': {
          runAfter: {
            'Determine_Scale_Action': [
              'Succeeded'
              'Failed'
              'Skipped'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'delete'
            path: concat('/@{encodeURIComponent(encodeURIComponent(\'', remediationTopicName, '\'))}/subscriptions/@{encodeURIComponent(\'auto-scale-handler\')}/messages/complete')
            queries: {
              lockToken: '@triggerBody()?[\'LockToken\']'
              subscriptionType: 'Main'
            }
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          servicebus: {
            connectionId: serviceBusConnection.id
            connectionName: serviceBusConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'servicebus')
          }
        }
      }
    }
  }
}

// Outputs
@description('Orchestrator Logic App trigger URL')
@secure()
output orchestratorTriggerUrl string = listCallbackUrl('${orchestratorLogicApp.id}/triggers/When_a_resource_health_alert_is_fired', '2019-05-01').value

@description('Orchestrator Logic App resource ID')
output orchestratorLogicAppId string = orchestratorLogicApp.id

@description('Restart handler Logic App resource ID')
output restartHandlerLogicAppId string = restartHandlerLogicApp.id

@description('Scale handler Logic App resource ID')
output scaleHandlerLogicAppId string = scaleHandlerLogicApp.id

@description('Service Bus connection resource ID')
output serviceBusConnectionId string = serviceBusConnection.id