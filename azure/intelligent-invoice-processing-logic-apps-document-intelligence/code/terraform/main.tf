# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Resource Group for all invoice processing resources
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = merge(var.tags, {
    Environment = var.environment
  })
}

# Storage Account for invoice documents and workflow data
resource "azurerm_storage_account" "invoices" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Enable hierarchical namespace for data lake scenarios
  is_hns_enabled = true
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Enable change feed for Event Grid integration
  blob_properties {
    change_feed_enabled = true
    versioning_enabled  = true
    
    # Configure lifecycle management
    delete_retention_policy {
      days = 30
    }
    
    container_delete_retention_policy {
      days = 30
    }
  }
  
  # Network access rules
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action             = "Deny"
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = []
      bypass                     = ["AzureServices"]
    }
  }
  
  tags = var.tags
}

# Storage containers for different invoice processing stages
resource "azurerm_storage_container" "invoices" {
  name                  = "invoices"
  storage_account_name  = azurerm_storage_account.invoices.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "processed" {
  name                  = "processed-invoices"
  storage_account_name  = azurerm_storage_account.invoices.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "failed" {
  name                  = "failed-processing"
  storage_account_name  = azurerm_storage_account.invoices.name
  container_access_type = "private"
}

# Azure AI Document Intelligence (Form Recognizer) service
resource "azurerm_cognitive_account" "document_intelligence" {
  name                = "di-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "FormRecognizer"
  sku_name            = var.document_intelligence_sku
  
  # Custom domain for API access
  custom_question_answering_search_service_id = null
  
  # Network access configuration
  public_network_access_enabled = true
  
  tags = var.tags
}

# Service Bus Namespace for enterprise messaging
resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.service_bus_sku
  
  tags = var.tags
}

# Service Bus Topic for invoice processing events
resource "azurerm_servicebus_topic" "invoice_processing" {
  name         = "invoice-processing"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Message retention and size limits
  max_message_size_in_kilobytes = 256
  default_message_ttl          = "P14D"  # 14 days
  duplicate_detection_history_time_window = "PT10M"  # 10 minutes
  
  # Enable partitioning for higher throughput
  partitioning_enabled = var.service_bus_sku == "Premium" ? true : false
}

# Service Bus Queue for processed invoices
resource "azurerm_servicebus_queue" "processed_invoices" {
  name         = "processed-invoices"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Message handling configuration
  max_delivery_count               = 10
  default_message_ttl             = "P14D"  # 14 days
  lock_duration                   = "PT5M"  # 5 minutes
  duplicate_detection_history_time_window = "PT10M"  # 10 minutes
  
  # Dead letter configuration
  dead_lettering_on_message_expiration = true
  
  # Enable sessions for ordered processing
  requires_session = false
}

# Service Bus Queue for approval workflows
resource "azurerm_servicebus_queue" "approval_queue" {
  name         = "approval-queue"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  max_delivery_count               = 5
  default_message_ttl             = "P7D"   # 7 days
  lock_duration                   = "PT10M" # 10 minutes
  dead_lettering_on_message_expiration = true
  requires_session = false
}

# Application Insights for monitoring and telemetry
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  tags = var.tags
}

# Function App Service Plan
resource "azurerm_service_plan" "function_plan" {
  name                = "plan-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.function_app_sku
  
  tags = var.tags
}

# Function App for advanced invoice processing
resource "azurerm_linux_function_app" "invoice_processor" {
  name                = "fa-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.function_plan.id
  storage_account_name       = azurerm_storage_account.invoices.name
  storage_account_access_key = azurerm_storage_account.invoices.primary_access_key
  
  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    # Enable Application Insights if monitoring is enabled
    application_insights_key               = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"        = "python"
    "DOCUMENT_INTELLIGENCE_ENDPOINT"  = azurerm_cognitive_account.document_intelligence.endpoint
    "DOCUMENT_INTELLIGENCE_KEY"       = azurerm_cognitive_account.document_intelligence.primary_access_key
    "SERVICE_BUS_CONNECTION_STRING"   = azurerm_servicebus_namespace.main.default_primary_connection_string
    "STORAGE_CONNECTION_STRING"       = azurerm_storage_account.invoices.primary_connection_string
    "INVOICE_APPROVAL_THRESHOLD"      = var.invoice_approval_threshold
    "APPROVER_EMAIL"                  = var.approver_email
  }
  
  tags = var.tags
}

# Event Grid System Topic for Storage Account events
resource "azurerm_eventgrid_system_topic" "storage_events" {
  name                   = "eg-storage-${random_string.suffix.result}"
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  source_arm_resource_id = azurerm_storage_account.invoices.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
  
  tags = var.tags
}

# Logic App (Consumption) for invoice processing workflow
resource "azurerm_logic_app_workflow" "invoice_processor" {
  name                = "la-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Workflow definition with comprehensive invoice processing logic
  workflow_definition = jsonencode({
    "$schema" = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "contentVersion" = "1.0.0.0",
    "parameters" = {
      "storageAccountName" = {
        "type" = "string",
        "defaultValue" = azurerm_storage_account.invoices.name
      },
      "documentIntelligenceEndpoint" = {
        "type" = "string",
        "defaultValue" = azurerm_cognitive_account.document_intelligence.endpoint
      },
      "serviceBusConnectionString" = {
        "type" = "string",
        "defaultValue" = azurerm_servicebus_namespace.main.default_primary_connection_string
      },
      "approvalThreshold" = {
        "type" = "int",
        "defaultValue" = var.invoice_approval_threshold
      },
      "approverEmail" = {
        "type" = "string",
        "defaultValue" = var.approver_email
      }
    },
    "triggers" = {
      "When_a_blob_is_added_or_modified" = {
        "type" = "ApiConnection",
        "inputs" = {
          "host" = {
            "connection" = {
              "name" = "@parameters('$connections')['azureblob']['connectionId']"
            }
          },
          "method" = "get",
          "path" = "/triggers/batch/onupdatedfile",
          "queries" = {
            "folderId" = "/invoices",
            "maxFileCount" = 10
          }
        },
        "recurrence" = {
          "frequency" = "Minute",
          "interval" = 1
        }
      }
    },
    "actions" = {
      "Initialize_Processing_Variables" = {
        "type" = "InitializeVariable",
        "inputs" = {
          "variables" = [
            {
              "name" = "ProcessingStatus",
              "type" = "string",
              "value" = "started"
            },
            {
              "name" = "InvoiceAmount",
              "type" = "float",
              "value" = 0
            },
            {
              "name" = "VendorName",
              "type" = "string",
              "value" = ""
            }
          ]
        },
        "runAfter" = {}
      },
      "Process_Invoice_with_AI" = {
        "type" = "Http",
        "inputs" = {
          "method" = "POST",
          "uri" = "@{parameters('documentIntelligenceEndpoint')}/formrecognizer/documentModels/prebuilt-invoice:analyze?api-version=2024-11-30",
          "headers" = {
            "Ocp-Apim-Subscription-Key" = "@{listKeys(resourceId('Microsoft.CognitiveServices/accounts', '${azurerm_cognitive_account.document_intelligence.name}'), '2023-05-01').key1}",
            "Content-Type" = "application/json"
          },
          "body" = {
            "urlSource" = "@{triggerBody().Path}"
          }
        },
        "runAfter" = {
          "Initialize_Processing_Variables" = ["Succeeded"]
        }
      },
      "Parse_Invoice_Data" = {
        "type" = "ParseJson",
        "inputs" = {
          "content" = "@body('Process_Invoice_with_AI')",
          "schema" = {
            "type" = "object",
            "properties" = {
              "analyzeResult" = {
                "type" = "object",
                "properties" = {
                  "documents" = {
                    "type" = "array",
                    "items" = {
                      "type" = "object",
                      "properties" = {
                        "fields" = {
                          "type" = "object",
                          "properties" = {
                            "InvoiceTotal" = {
                              "type" = "object",
                              "properties" = {
                                "content" = {
                                  "type" = "string"
                                }
                              }
                            },
                            "VendorName" = {
                              "type" = "object",
                              "properties" = {
                                "content" = {
                                  "type" = "string"
                                }
                              }
                            },
                            "InvoiceDate" = {
                              "type" = "object",
                              "properties" = {
                                "content" = {
                                  "type" = "string"
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
        },
        "runAfter" = {
          "Process_Invoice_with_AI" = ["Succeeded"]
        }
      },
      "Set_Invoice_Variables" = {
        "type" = "SetVariable",
        "inputs" = {
          "name" = "InvoiceAmount",
          "value" = "@float(coalesce(body('Parse_Invoice_Data')?['analyzeResult']?['documents']?[0]?['fields']?['InvoiceTotal']?['content'], '0'))"
        },
        "runAfter" = {
          "Parse_Invoice_Data" = ["Succeeded"]
        }
      },
      "Check_Invoice_Amount" = {
        "type" = "If",
        "expression" = {
          "greater" = [
            "@variables('InvoiceAmount')",
            "@parameters('approvalThreshold')"
          ]
        },
        "actions" = {
          "Send_for_Approval" = {
            "type" = "ApiConnection",
            "inputs" = {
              "host" = {
                "connection" = {
                  "name" = "@parameters('$connections')['office365']['connectionId']"
                }
              },
              "method" = "post",
              "path" = "/v2/Mail",
              "body" = {
                "To" = "@parameters('approverEmail')",
                "Subject" = "Invoice Approval Required - Amount: $@{variables('InvoiceAmount')}",
                "Body" = "Invoice from @{coalesce(body('Parse_Invoice_Data')?['analyzeResult']?['documents']?[0]?['fields']?['VendorName']?['content'], 'Unknown Vendor')} requires approval.<br/><br/>Amount: $@{variables('InvoiceAmount')}<br/>Date: @{coalesce(body('Parse_Invoice_Data')?['analyzeResult']?['documents']?[0]?['fields']?['InvoiceDate']?['content'], 'Unknown Date')}<br/><br/>Please review the document and approve or reject."
              }
            }
          },
          "Set_Approval_Status" = {
            "type" = "SetVariable",
            "inputs" = {
              "name" = "ProcessingStatus",
              "value" = "pending_approval"
            },
            "runAfter" = {
              "Send_for_Approval" = ["Succeeded"]
            }
          }
        },
        "else" = {
          "actions" = {
            "Auto_Approve" = {
              "type" = "SetVariable",
              "inputs" = {
                "name" = "ProcessingStatus",
                "value" = "auto_approved"
              }
            }
          }
        },
        "runAfter" = {
          "Set_Invoice_Variables" = ["Succeeded"]
        }
      },
      "Send_to_Service_Bus" = {
        "type" = "ApiConnection",
        "inputs" = {
          "host" = {
            "connection" = {
              "name" = "@parameters('$connections')['servicebus']['connectionId']"
            }
          },
          "method" = "post",
          "path" = "/queues/@{encodeURIComponent('processed-invoices')}/messages",
          "body" = {
            "ContentData" = "@{base64(string(body('Parse_Invoice_Data')))}"
          }
        },
        "runAfter" = {
          "Check_Invoice_Amount" = ["Succeeded"]
        }
      },
      "Move_to_Processed_Container" = {
        "type" = "ApiConnection",
        "inputs" = {
          "host" = {
            "connection" = {
              "name" = "@parameters('$connections')['azureblob']['connectionId']"
            }
          },
          "method" = "post",
          "path" = "/copyblob",
          "queries" = {
            "source" = "@triggerBody().Path",
            "destination" = "/processed-invoices/@{triggerBody().Name}",
            "overwrite" = true
          }
        },
        "runAfter" = {
          "Send_to_Service_Bus" = ["Succeeded"]
        }
      }
    },
    "outputs" = {}
  })
  
  tags = var.tags
}

# API Connections for Logic App integrations
resource "azurerm_api_connection" "blob_connection" {
  name                = "blob-connection-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/azureblob"
  
  parameter_values = {
    accountName = azurerm_storage_account.invoices.name
    accessKey   = azurerm_storage_account.invoices.primary_access_key
  }
  
  tags = var.tags
}

resource "azurerm_api_connection" "servicebus_connection" {
  name                = "servicebus-connection-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/servicebus"
  
  parameter_values = {
    connectionString = azurerm_servicebus_namespace.main.default_primary_connection_string
  }
  
  tags = var.tags
}

resource "azurerm_api_connection" "office365_connection" {
  name                = "office365-connection-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/office365"
  
  # Note: Office 365 connection requires OAuth authentication
  # This will need to be configured manually or through Azure portal
  display_name = "Office 365 Outlook Connection"
  
  tags = var.tags
}

# Event Grid Event Subscription for blob creation events
resource "azurerm_eventgrid_event_subscription" "blob_created" {
  name  = "invoice-upload-subscription"
  scope = azurerm_storage_account.invoices.id
  
  # Webhook endpoint pointing to Logic App trigger
  webhook_endpoint {
    url = "https://${azurerm_logic_app_workflow.invoice_processor.name}.logic.azure.com/workflows/${azurerm_logic_app_workflow.invoice_processor.name}/triggers/manual/paths/invoke"
  }
  
  # Filter for blob creation events in the invoices container
  subject_filter {
    subject_begins_with = "/blobServices/default/containers/${azurerm_storage_container.invoices.name}/"
  }
  
  included_event_types = [
    "Microsoft.Storage.BlobCreated"
  ]
  
  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440  # 24 hours
  }
}

# Azure Key Vault for secure secrets management (optional but recommended)
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Enable soft delete and purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  # Access policy for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover",
      "Backup",
      "Restore"
    ]
  }
  
  tags = var.tags
}

# Store sensitive configuration in Key Vault
resource "azurerm_key_vault_secret" "document_intelligence_key" {
  name         = "document-intelligence-key"
  value        = azurerm_cognitive_account.document_intelligence.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.invoices.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "servicebus_connection_string" {
  name         = "servicebus-connection-string"
  value        = azurerm_servicebus_namespace.main.default_primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}