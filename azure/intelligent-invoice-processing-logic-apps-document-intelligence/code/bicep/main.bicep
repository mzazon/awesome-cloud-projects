@description('Main Bicep template for Intelligent Invoice Processing Workflows with Azure Logic Apps and AI Document Intelligence')

// Parameters with validation and descriptions
@description('The Azure region to deploy resources to')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource naming to ensure global uniqueness')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Storage account SKU for invoice storage')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('AI Document Intelligence pricing tier')
@allowed(['F0', 'S0'])
param documentIntelligenceSku string = 'S0'

@description('Service Bus namespace SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param serviceBusNamespaceSku string = 'Standard'

@description('Enable blob change feed for Event Grid integration')
param enableBlobChangeFeed bool = true

@description('Logic App definition for the invoice processing workflow')
param logicAppDefinition object = {}

@description('Email address for invoice approval notifications')
param approverEmailAddress string = 'finance-approver@company.com'

@description('Invoice amount threshold for approval workflow')
@minValue(0)
param approvalThreshold int = 1000

@description('Resource tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Purpose: 'invoice-processing'
  CreatedBy: 'bicep-template'
}

// Variables for resource naming
var namePrefix = 'invoice-${environment}-${uniqueSuffix}'
var storageAccountName = 'st${replace(namePrefix, '-', '')}'
var documentIntelligenceName = 'di-${namePrefix}'
var logicAppName = 'la-${namePrefix}'
var serviceBusNamespaceName = 'sb-${namePrefix}'
var functionAppName = 'fa-${namePrefix}'
var appServicePlanName = 'asp-${namePrefix}'
var eventGridTopicName = 'egt-${namePrefix}'

// Storage Account for invoice documents
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Blob Services for storage account
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: enableBlobChangeFeed
      retentionInDays: 7
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    versioning: {
      enabled: true
    }
  }
}

// Invoice container
resource invoiceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'invoices'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'invoice-storage'
    }
  }
}

// Processed documents container
resource processedContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'processed'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'processed-invoice-storage'
    }
  }
}

// AI Document Intelligence service
resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: documentIntelligenceName
  location: location
  tags: resourceTags
  sku: {
    name: documentIntelligenceSku
  }
  kind: 'FormRecognizer'
  properties: {
    customSubDomainName: documentIntelligenceName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Service Bus namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: resourceTags
  sku: {
    name: serviceBusNamespaceSku
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Service Bus topic for invoice processing events
resource invoiceProcessingTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'invoice-processing'
  properties: {
    defaultMessageTimeToLive: 'P14D'
    enableBatchedOperations: true
    enablePartitioning: false
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    supportOrdering: true
  }
}

// Service Bus queue for processed invoices
resource processedInvoicesQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'processed-invoices'
  properties: {
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    enableBatchedOperations: true
    enablePartitioning: false
    maxDeliveryCount: 10
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
  }
}

// Service Bus subscription for ERP integration
resource erpSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: invoiceProcessingTopic
  name: 'erp-integration'
  properties: {
    defaultMessageTimeToLive: 'P14D'
    enableBatchedOperations: true
    maxDeliveryCount: 10
    requiresSession: false
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: resourceTags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false
  }
}

// Function App for additional processing
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  tags: resourceTags
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'DOCUMENT_INTELLIGENCE_ENDPOINT'
          value: documentIntelligence.properties.endpoint
        }
        {
          name: 'DOCUMENT_INTELLIGENCE_KEY'
          value: documentIntelligence.listKeys().key1
        }
        {
          name: 'SERVICE_BUS_CONNECTION'
          value: listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'STORAGE_ACCOUNT_KEY'
          value: storageAccount.listKeys().keys[0].value
        }
      ]
      pythonVersion: '3.11'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

// Event Grid System Topic for storage events
resource eventGridTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: resourceTags
  properties: {
    source: storageAccount.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// Logic App with comprehensive workflow definition
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: resourceTags
  properties: {
    definition: empty(logicAppDefinition) ? {
      '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
        documentIntelligenceEndpoint: {
          type: 'String'
          defaultValue: documentIntelligence.properties.endpoint
        }
        documentIntelligenceKey: {
          type: 'String'
          defaultValue: documentIntelligence.listKeys().key1
        }
        storageAccountName: {
          type: 'String'
          defaultValue: storageAccount.name
        }
        approverEmail: {
          type: 'String'
          defaultValue: approverEmailAddress
        }
        approvalThreshold: {
          type: 'Int'
          defaultValue: approvalThreshold
        }
      }
      triggers: {
        When_a_blob_is_added_or_modified: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/triggers/batch/onupdatedfile'
            queries: {
              folderId: '/invoices'
              maxFileCount: 10
            }
          }
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
        }
      }
      actions: {
        Initialize_invoice_metadata: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'InvoiceMetadata'
                type: 'Object'
                value: {
                  fileName: '@triggerBody()?[\'Name\']'
                  fileSize: '@triggerBody()?[\'Size\']'
                  lastModified: '@triggerBody()?[\'LastModified\']'
                  blobUri: '@triggerBody()?[\'Path\']'
                  processedAt: '@utcNow()'
                }
              }
            ]
          }
          runAfter: {}
        }
        Process_Invoice_with_AI: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@{parameters(\'documentIntelligenceEndpoint\')}/formrecognizer/documentModels/prebuilt-invoice:analyze?api-version=2023-07-31'
            headers: {
              'Ocp-Apim-Subscription-Key': '@parameters(\'documentIntelligenceKey\')'
              'Content-Type': 'application/json'
            }
            body: {
              urlSource: '@triggerBody()?[\'MediaLink\']'
            }
          }
          runAfter: {
            Initialize_invoice_metadata: [
              'Succeeded'
            ]
          }
        }
        Get_analysis_result: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '@body(\'Process_Invoice_with_AI\')?[\'headers\']?[\'Operation-Location\']'
            headers: {
              'Ocp-Apim-Subscription-Key': '@parameters(\'documentIntelligenceKey\')'
            }
          }
          runAfter: {
            Wait_for_analysis: [
              'Succeeded'
            ]
          }
        }
        Wait_for_analysis: {
          type: 'Wait'
          inputs: {
            interval: {
              count: 10
              unit: 'Second'
            }
          }
          runAfter: {
            Process_Invoice_with_AI: [
              'Succeeded'
            ]
          }
        }
        Parse_Invoice_Data: {
          type: 'ParseJson'
          inputs: {
            content: '@body(\'Get_analysis_result\')'
            schema: {
              type: 'object'
              properties: {
                status: {
                  type: 'string'
                }
                analyzeResult: {
                  type: 'object'
                  properties: {
                    documents: {
                      type: 'array'
                      items: {
                        type: 'object'
                        properties: {
                          fields: {
                            type: 'object'
                            properties: {
                              InvoiceTotal: {
                                type: 'object'
                                properties: {
                                  content: {
                                    type: 'string'
                                  }
                                  confidence: {
                                    type: 'number'
                                  }
                                }
                              }
                              VendorName: {
                                type: 'object'
                                properties: {
                                  content: {
                                    type: 'string'
                                  }
                                  confidence: {
                                    type: 'number'
                                  }
                                }
                              }
                              InvoiceDate: {
                                type: 'object'
                                properties: {
                                  content: {
                                    type: 'string'
                                  }
                                  confidence: {
                                    type: 'number'
                                  }
                                }
                              }
                              InvoiceId: {
                                type: 'object'
                                properties: {
                                  content: {
                                    type: 'string'
                                  }
                                  confidence: {
                                    type: 'number'
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          runAfter: {
            Get_analysis_result: [
              'Succeeded'
            ]
          }
        }
        Check_Invoice_Amount: {
          type: 'If'
          expression: {
            greater: [
              '@float(coalesce(body(\'Parse_Invoice_Data\')?[\'analyzeResult\']?[\'documents\']?[0]?[\'fields\']?[\'InvoiceTotal\']?[\'content\'], \'0\'))'
              '@parameters(\'approvalThreshold\')'
            ]
          }
          actions: {
            Send_for_Approval: {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/v2/Mail'
                body: {
                  To: '@parameters(\'approverEmail\')'
                  Subject: 'Invoice Approval Required - @{body(\'Parse_Invoice_Data\')?[\'analyzeResult\']?[\'documents\']?[0]?[\'fields\']?[\'VendorName\']?[\'content\']}'
                  Body: '<h2>Invoice Approval Required</h2><p><strong>Vendor:</strong> @{body(\'Parse_Invoice_Data\')?[\'analyzeResult\']?[\'documents\']?[0]?[\'fields\']?[\'VendorName\']?[\'content\']}</p><p><strong>Amount:</strong> $@{body(\'Parse_Invoice_Data\')?[\'analyzeResult\']?[\'documents\']?[0]?[\'fields\']?[\'InvoiceTotal\']?[\'content\']}</p><p><strong>Invoice ID:</strong> @{body(\'Parse_Invoice_Data\')?[\'analyzeResult\']?[\'documents\']?[0]?[\'fields\']?[\'InvoiceId\']?[\'content\']}</p><p><strong>Date:</strong> @{body(\'Parse_Invoice_Data\')?[\'analyzeResult\']?[\'documents\']?[0]?[\'fields\']?[\'InvoiceDate\']?[\'content\']}</p><p>This invoice exceeds the approval threshold of $@{parameters(\'approvalThreshold\')} and requires manual approval.</p>'
                  Importance: 'High'
                  IsHtml: true
                }
              }
            }
            Set_approval_status_manual: {
              type: 'SetVariable'
              inputs: {
                name: 'ApprovalStatus'
                value: 'pending_approval'
              }
              runAfter: {
                Send_for_Approval: [
                  'Succeeded'
                ]
              }
            }
          }
          'else': {
            actions: {
              Set_approval_status_auto: {
                type: 'SetVariable'
                inputs: {
                  name: 'ApprovalStatus'
                  value: 'auto_approved'
                }
              }
            }
          }
          runAfter: {
            Initialize_approval_status: [
              'Succeeded'
            ]
          }
        }
        Initialize_approval_status: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'ApprovalStatus'
                type: 'String'
                value: 'pending'
              }
            ]
          }
          runAfter: {
            Parse_Invoice_Data: [
              'Succeeded'
            ]
          }
        }
        Send_to_Service_Bus: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/topics/@{encodeURIComponent(\'invoice-processing\')}/messages'
            body: {
              ContentData: '@{base64(string(createObject(\'invoiceData\', body(\'Parse_Invoice_Data\')?[\'analyzeResult\']?[\'documents\']?[0]?[\'fields\'], \'metadata\', variables(\'InvoiceMetadata\'), \'approvalStatus\', variables(\'ApprovalStatus\'), \'processedTimestamp\', utcNow())))}'
              Properties: {
                invoiceId: '@{body(\'Parse_Invoice_Data\')?[\'analyzeResult\']?[\'documents\']?[0]?[\'fields\']?[\'InvoiceId\']?[\'content\']}'
                vendorName: '@{body(\'Parse_Invoice_Data\')?[\'analyzeResult\']?[\'documents\']?[0]?[\'fields\']?[\'VendorName\']?[\'content\']}'
                totalAmount: '@{body(\'Parse_Invoice_Data\')?[\'analyzeResult\']?[\'documents\']?[0]?[\'fields\']?[\'InvoiceTotal\']?[\'content\']}'
                approvalStatus: '@{variables(\'ApprovalStatus\')}'
              }
            }
          }
          runAfter: {
            Check_Invoice_Amount: [
              'Succeeded'
            ]
          }
        }
        Copy_to_processed_container: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/copyFile'
            queries: {
              source: '@triggerBody()?[\'Path\']'
              destination: '/processed/@{formatDateTime(utcNow(), \'yyyy/MM/dd\')}/@{variables(\'InvoiceMetadata\')?[\'fileName\']}'
              overwrite: true
            }
          }
          runAfter: {
            Send_to_Service_Bus: [
              'Succeeded'
            ]
          }
        }
      }
      outputs: {}
    } : logicAppDefinition
  }
}

// API Connections for Logic App

// Azure Blob Storage connection
resource blobConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azureblob-connection'
  location: location
  tags: resourceTags
  properties: {
    displayName: 'Azure Blob Storage Connection'
    api: {
      id: '${subscription().id}/providers/Microsoft.Web/locations/${location}/managedApis/azureblob'
    }
    parameterValues: {
      accountName: storageAccount.name
      accessKey: storageAccount.listKeys().keys[0].value
    }
  }
}

// Service Bus connection
resource serviceBusConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'servicebus-connection'
  location: location
  tags: resourceTags
  properties: {
    displayName: 'Service Bus Connection'
    api: {
      id: '${subscription().id}/providers/Microsoft.Web/locations/${location}/managedApis/servicebus'
    }
    parameterValues: {
      connectionString: listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
    }
  }
}

// Office 365 connection for email notifications
resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'office365-connection'
  location: location
  tags: resourceTags
  properties: {
    displayName: 'Office 365 Outlook Connection'
    api: {
      id: '${subscription().id}/providers/Microsoft.Web/locations/${location}/managedApis/office365'
    }
    // Note: This connection requires manual authentication in the Azure portal
  }
}

// Event Grid subscription for blob created events
resource eventGridSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
  parent: eventGridTopic
  name: 'invoice-processing-subscription'
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: '${logicApp.properties.accessEndpoint}/triggers/When_a_blob_is_added_or_modified/run'
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
        'Microsoft.Storage.BlobDeleted'
      ]
      subjectBeginsWith: '/blobServices/default/containers/invoices/'
      subjectEndsWith: '.pdf'
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// Outputs
@description('Storage account name for invoice documents')
output storageAccountName string = storageAccount.name

@description('Storage account primary key')
@secure()
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('AI Document Intelligence service endpoint')
output documentIntelligenceEndpoint string = documentIntelligence.properties.endpoint

@description('AI Document Intelligence service key')
@secure()
output documentIntelligenceKey string = documentIntelligence.listKeys().key1

@description('Service Bus namespace connection string')
@secure()
output serviceBusConnectionString string = listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString

@description('Logic App name for the invoice processing workflow')
output logicAppName string = logicApp.name

@description('Logic App trigger endpoint URL')
output logicAppTriggerUrl string = '${logicApp.properties.accessEndpoint}/triggers/When_a_blob_is_added_or_modified/run'

@description('Function App name for additional processing')
output functionAppName string = functionApp.name

@description('Event Grid topic name for storage events')
output eventGridTopicName string = eventGridTopic.name

@description('Resource group location')
output deploymentLocation string = location

@description('Unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix

@description('Environment name')
output environment string = environment

@description('Invoice container URL')
output invoiceContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}invoices'

@description('Processed documents container URL')
output processedContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}processed'

@description('Service Bus topic name for invoice processing')
output serviceBusTopicName string = invoiceProcessingTopic.name

@description('Service Bus queue name for processed invoices')
output serviceBusQueueName string = processedInvoicesQueue.name