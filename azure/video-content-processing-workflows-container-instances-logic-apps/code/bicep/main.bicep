@description('Main Bicep template for Azure Video Content Processing Workflow')
@description('This template deploys Azure Container Instances, Logic Apps, Event Grid, and Blob Storage for automated video processing')

// Parameters
@description('Specifies the Azure region for all resources')
param location string = resourceGroup().location

@description('Environment name for resource naming (e.g., dev, staging, prod)')
@minLength(2)
@maxLength(10)
param environmentName string = 'demo'

@description('Unique suffix for resource names to ensure global uniqueness')
@minLength(3)
@maxLength(8)
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Storage account tier for video storage')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountTier string = 'Standard_LRS'

@description('Container CPU allocation for video processing')
@minValue(1)
@maxValue(4)
param containerCpuCores int = 2

@description('Container memory allocation in GB for video processing')
@minValue(1)
@maxValue(16)
param containerMemoryInGb int = 4

@description('FFmpeg container image for video processing')
param ffmpegContainerImage string = 'jrottenberg/ffmpeg:latest'

@description('Tags to apply to all resources')
param resourceTags object = {
  Purpose: 'VideoProcessing'
  Environment: environmentName
  ManagedBy: 'Bicep'
  Recipe: 'AutomatingVideoContentProcessing'
}

// Variables
var storageAccountName = 'st${environmentName}video${uniqueSuffix}'
var logicAppName = 'la-video-processor-${environmentName}-${uniqueSuffix}'
var eventGridTopicName = 'egt-video-events-${environmentName}-${uniqueSuffix}'
var containerGroupName = 'cg-video-ffmpeg-${environmentName}-${uniqueSuffix}'
var inputContainerName = 'input-videos'
var outputContainerName = 'output-videos'

// Storage Account for video files
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountTier
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
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
      bypass: 'AzureServices'
    }
  }
}

// Blob service for storage account
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
  }
}

// Input container for video uploads
resource inputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: inputContainerName
  properties: {
    publicAccess: 'None'
    metadata: {
      Purpose: 'VideoInputStorage'
    }
  }
}

// Output container for processed videos
resource outputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: outputContainerName
  properties: {
    publicAccess: 'None'
    metadata: {
      Purpose: 'VideoOutputStorage'
    }
  }
}

// Event Grid Topic for video processing events
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: resourceTags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
  }
}

// Logic App for workflow orchestration
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: resourceTags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        storageAccountName: {
          type: 'string'
          defaultValue: storageAccountName
        }
        containerGroupName: {
          type: 'string'
          defaultValue: containerGroupName
        }
        resourceGroupName: {
          type: 'string'
          defaultValue: resourceGroup().name
        }
        subscriptionId: {
          type: 'string'
          defaultValue: subscription().subscriptionId
        }
      }
      triggers: {
        'When_a_blob_is_added_or_modified': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/default/triggers/batch/onupdatedfile'
            queries: {
              folderId: 'JTJmaW5wdXQtdmlkZW9z' // Base64 encoded '/input-videos'
              maxFileCount: 1
            }
          }
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          splitOn: '@triggerBody()'
        }
      }
      actions: {
        'Parse_blob_metadata': {
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()'
            schema: {
              type: 'object'
              properties: {
                Id: { type: 'string' }
                Name: { type: 'string' }
                Path: { type: 'string' }
                MediaType: { type: 'string' }
                Size: { type: 'integer' }
              }
            }
          }
        }
        'Create_container_for_processing': {
          type: 'Http'
          inputs: {
            method: 'PUT'
            uri: 'https://management.azure.com/subscriptions/@{parameters(\'subscriptionId\')}/resourceGroups/@{parameters(\'resourceGroupName\')}/providers/Microsoft.ContainerInstance/containerGroups/@{parameters(\'containerGroupName\')}'
            headers: {
              'Content-Type': 'application/json'
              Authorization: 'Bearer @{body(\'Get_access_token\')?[\'access_token\']}'
            }
            body: {
              location: location
              properties: {
                containers: [
                  {
                    name: 'ffmpeg-processor'
                    properties: {
                      image: ffmpegContainerImage
                      resources: {
                        requests: {
                          cpu: containerCpuCores
                          memoryInGB: containerMemoryInGb
                        }
                      }
                      environmentVariables: [
                        {
                          name: 'STORAGE_ACCOUNT_NAME'
                          value: '@parameters(\'storageAccountName\')'
                        }
                        {
                          name: 'INPUT_BLOB_NAME'
                          value: '@body(\'Parse_blob_metadata\')?[\'Name\']'
                        }
                        {
                          name: 'AZURE_STORAGE_CONNECTION_STRING'
                          secureValue: '@listKeys(resourceId(\'Microsoft.Storage/storageAccounts\', parameters(\'storageAccountName\')), \'2023-01-01\').keys[0].value'
                        }
                      ]
                      command: [
                        '/bin/bash'
                        '-c'
                        'echo "Processing video: $INPUT_BLOB_NAME" && ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /tmp/processed_video.mp4 && echo "Video processing completed"'
                      ]
                    }
                  }
                ]
                osType: 'Linux'
                restartPolicy: 'Never'
              }
            }
          }
          runAfter: {
            'Get_access_token': ['Succeeded']
          }
        }
        'Get_access_token': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://login.microsoftonline.com/@{subscription().tenantId}/oauth2/token'
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded'
            }
            body: 'grant_type=client_credentials&client_id=@{parameters(\'managedIdentityClientId\')}&resource=https://management.azure.com/'
          }
          runAfter: {
            'Parse_blob_metadata': ['Succeeded']
          }
        }
        'Send_completion_notification': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: eventGridTopic.properties.endpoint
            headers: {
              'Content-Type': 'application/json'
              'aeg-sas-key': listKeys(eventGridTopic.id, '2023-12-15-preview').key1
            }
            body: {
              id: '@{guid()}'
              eventType: 'VideoProcessing.Completed'
              subject: 'video-processing'
              eventTime: '@{utcNow()}'
              data: {
                inputFile: '@body(\'Parse_blob_metadata\')?[\'Name\']'
                status: 'completed'
                processingTime: '@{utcNow()}'
              }
              dataVersion: '1.0'
            }
          }
          runAfter: {
            'Create_container_for_processing': ['Succeeded']
          }
        }
      }
    }
  }
}

// Managed Identity for Logic App
resource logicAppManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-${logicAppName}'
  location: location
  tags: resourceTags
}

// Role assignment for Logic App to manage Container Instances
resource containerInstanceContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, logicAppManagedIdentity.id, 'ContainerInstanceContributor')
  scope: resourceGroup()
  properties: {
    principalId: logicAppManagedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e1e49798-5d59-4312-8e2a-46b95b9ba6df') // Container Instance Contributor
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Logic App to access storage
resource storageContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, logicAppManagedIdentity.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    principalId: logicAppManagedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalType: 'ServicePrincipal'
  }
}

// Event Grid subscription for blob storage events
resource eventGridSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: 'video-upload-subscription'
  scope: storageAccount
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: '${logicApp.properties.accessEndpoint}/triggers/When_a_blob_is_added_or_modified/paths/invoke'
      }
    }
    filter: {
      subjectBeginsWith: '/blobServices/default/containers/${inputContainerName}/'
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
  }
  dependsOn: [
    inputContainer
  ]
}

// Container group for video processing (template - will be created dynamically by Logic App)
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  tags: resourceTags
  properties: {
    containers: [
      {
        name: 'ffmpeg-processor'
        properties: {
          image: ffmpegContainerImage
          resources: {
            requests: {
              cpu: containerCpuCores
              memoryInGB: containerMemoryInGb
            }
          }
          environmentVariables: [
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storageAccountName
            }
            {
              name: 'AZURE_STORAGE_CONNECTION_STRING'
              secureValue: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
            }
          ]
          command: [
            'tail'
            '-f'
            '/dev/null'
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Never'
  }
}

// Outputs
@description('Storage account name for video files')
output storageAccountName string = storageAccount.name

@description('Storage account primary endpoint')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Input container name for video uploads')
output inputContainerName string = inputContainer.name

@description('Output container name for processed videos')
output outputContainerName string = outputContainer.name

@description('Logic App name for workflow orchestration')
output logicAppName string = logicApp.name

@description('Logic App trigger URL for manual testing')
output logicAppTriggerUrl string = '${logicApp.properties.accessEndpoint}/triggers/When_a_blob_is_added_or_modified/paths/invoke'

@description('Event Grid topic name for video processing events')
output eventGridTopicName string = eventGridTopic.name

@description('Event Grid topic endpoint for custom events')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('Container group name for video processing')
output containerGroupName string = containerGroup.name

@description('Storage account connection string for applications')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Resource group name where all resources are deployed')
output resourceGroupName string = resourceGroup().name

@description('Azure region where resources are deployed')
output deploymentLocation string = location

@description('Unique suffix used for resource naming')
output uniqueResourceSuffix string = uniqueSuffix

@description('Managed Identity ID for Logic App')
output logicAppManagedIdentityId string = logicAppManagedIdentity.id

@description('All resource names created by this template')
output createdResources object = {
  storageAccount: storageAccount.name
  logicApp: logicApp.name
  eventGridTopic: eventGridTopic.name
  containerGroup: containerGroup.name
  managedIdentity: logicAppManagedIdentity.name
  inputContainer: inputContainer.name
  outputContainer: outputContainer.name
}