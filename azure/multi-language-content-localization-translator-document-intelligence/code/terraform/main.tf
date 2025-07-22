# Main Terraform configuration for Azure multi-language content localization workflow
# This configuration creates a complete automated document translation system

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create resource group for all localization resources
resource "azurerm_resource_group" "localization" {
  name     = var.resource_group_name
  location = var.location
  tags = merge(var.tags, {
    Purpose = "Multi-language content localization workflow"
  })
}

# Create storage account for document workflow
resource "azurerm_storage_account" "documents" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.localization.name
  location                 = azurerm_resource_group.localization.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable blob versioning and soft delete for data protection
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }
  
  # Enable static website hosting for potential web interface
  static_website {
    index_document = "index.html"
  }
  
  tags = var.tags
}

# Create storage containers for document workflow stages
resource "azurerm_storage_container" "source_documents" {
  name                  = "source-documents"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "processing_workspace" {
  name                  = "processing-workspace"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "localized_output" {
  name                  = "localized-output"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "workflow_logs" {
  name                  = "workflow-logs"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

# Create Azure Translator service for multi-language translation
resource "azurerm_cognitive_account" "translator" {
  name                = "translator-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.localization.name
  location            = azurerm_resource_group.localization.location
  kind                = "TextTranslation"
  sku_name            = var.translator_sku
  
  # Enable custom subdomain for enhanced security
  custom_subdomain_name = "translator-${var.project_name}-${random_string.suffix.result}"
  
  # Configure network access rules for security
  network_acls {
    default_action = "Allow"
    ip_rules       = []
    virtual_network_rules {
      subnet_id                            = azurerm_subnet.localization.id
      ignore_missing_vnet_service_endpoint = false
    }
  }
  
  tags = var.tags
}

# Create Azure Document Intelligence service for text extraction
resource "azurerm_cognitive_account" "document_intelligence" {
  name                = "doc-intel-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.localization.name
  location            = azurerm_resource_group.localization.location
  kind                = "FormRecognizer"
  sku_name            = var.document_intelligence_sku
  
  # Enable custom subdomain for enhanced security
  custom_subdomain_name = "doc-intel-${var.project_name}-${random_string.suffix.result}"
  
  # Configure network access rules for security
  network_acls {
    default_action = "Allow"
    ip_rules       = []
    virtual_network_rules {
      subnet_id                            = azurerm_subnet.localization.id
      ignore_missing_vnet_service_endpoint = false
    }
  }
  
  tags = var.tags
}

# Create Virtual Network for secure service communication
resource "azurerm_virtual_network" "localization" {
  name                = "vnet-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.localization.name
  location            = azurerm_resource_group.localization.location
  address_space       = ["10.0.0.0/16"]
  
  tags = var.tags
}

# Create subnet for localization services
resource "azurerm_subnet" "localization" {
  name                 = "subnet-${var.project_name}"
  resource_group_name  = azurerm_resource_group.localization.name
  virtual_network_name = azurerm_virtual_network.localization.name
  address_prefixes     = ["10.0.1.0/24"]
  
  # Enable service endpoints for Azure services
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.CognitiveServices",
    "Microsoft.Web"
  ]
}

# Create Application Insights for monitoring (if enabled)
resource "azurerm_application_insights" "localization" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.localization.name
  location            = azurerm_resource_group.localization.location
  application_type    = "web"
  
  tags = var.tags
}

# Create API Connection for Azure Blob Storage
resource "azurerm_api_connection" "blob_storage" {
  name                = "azureblob-connection-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.localization.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.localization.location}/managedApis/azureblob"
  
  parameter_values = {
    accountName = azurerm_storage_account.documents.name
    accessKey   = azurerm_storage_account.documents.primary_access_key
  }
  
  tags = var.tags
}

# Create API Connection for Cognitive Services
resource "azurerm_api_connection" "cognitive_services" {
  name                = "cognitiveservices-connection-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.localization.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.localization.location}/managedApis/cognitiveservicestextanalytics"
  
  parameter_values = {
    apiKey  = azurerm_cognitive_account.document_intelligence.primary_access_key
    siteUrl = azurerm_cognitive_account.document_intelligence.endpoint
  }
  
  tags = var.tags
}

# Create Logic App for workflow orchestration
resource "azurerm_logic_app_workflow" "localization" {
  name                = "logic-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.localization.name
  location            = azurerm_resource_group.localization.location
  
  # Enhanced workflow definition with comprehensive localization logic
  workflow_definition = jsonencode({
    "$schema" = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
    contentVersion = "1.0.0.0"
    
    parameters = {
      "$connections" = {
        defaultValue = {}
        type = "Object"
      }
      "documentIntelligenceEndpoint" = {
        defaultValue = azurerm_cognitive_account.document_intelligence.endpoint
        type = "String"
      }
      "documentIntelligenceKey" = {
        defaultValue = azurerm_cognitive_account.document_intelligence.primary_access_key
        type = "String"
      }
      "translatorEndpoint" = {
        defaultValue = azurerm_cognitive_account.translator.endpoint
        type = "String"
      }
      "translatorKey" = {
        defaultValue = azurerm_cognitive_account.translator.primary_access_key
        type = "String"
      }
      "targetLanguages" = {
        defaultValue = var.target_languages
        type = "Array"
      }
    }
    
    triggers = {
      "When_a_blob_is_added_or_modified" = {
        type = "ApiConnection"
        inputs = {
          host = {
            connection = {
              name = "@parameters('$connections')['azureblob']['connectionId']"
            }
          }
          method = "get"
          path = "/datasets/default/triggers/batch/onupdatedfile"
          queries = {
            folderId = "source-documents"
            maxFileCount = 1
          }
        }
        recurrence = {
          frequency = "Minute"
          interval = var.logic_app_trigger_interval
        }
      }
    }
    
    actions = {
      "Log_Processing_Start" = {
        type = "ApiConnection"
        inputs = {
          host = {
            connection = {
              name = "@parameters('$connections')['azureblob']['connectionId']"
            }
          }
          method = "post"
          path = "/datasets/default/files"
          queries = {
            folderPath = "/workflow-logs"
            name = "@{concat('processing-', formatDateTime(utcNow(), 'yyyyMMdd-HHmmss'), '.log')}"
          }
          body = "@{concat('Processing started for: ', triggerBody()['Name'], ' at ', utcNow())}"
        }
      }
      
      "Get_Document_Content" = {
        type = "ApiConnection"
        inputs = {
          host = {
            connection = {
              name = "@parameters('$connections')['azureblob']['connectionId']"
            }
          }
          method = "get"
          path = "/datasets/default/files/@{encodeURIComponent(encodeURIComponent(triggerBody()['Id']))}/content"
        }
        runAfter = {
          "Log_Processing_Start" = ["Succeeded"]
        }
      }
      
      "Extract_Document_Text" = {
        type = "Http"
        inputs = {
          method = "POST"
          uri = "@{parameters('documentIntelligenceEndpoint')}/formrecognizer/documentModels/prebuilt-layout:analyze"
          headers = {
            "Ocp-Apim-Subscription-Key" = "@parameters('documentIntelligenceKey')"
            "Content-Type" = "application/json"
          }
          body = {
            urlSource = "@{triggerBody()['Path']}"
          }
          queries = {
            "api-version" = "2023-07-31"
          }
        }
        runAfter = {
          "Get_Document_Content" = ["Succeeded"]
        }
      }
      
      "Wait_for_Analysis" = {
        type = "Wait"
        inputs = {
          interval = {
            count = 10
            unit = "Second"
          }
        }
        runAfter = {
          "Extract_Document_Text" = ["Succeeded"]
        }
      }
      
      "Get_Analysis_Results" = {
        type = "Http"
        inputs = {
          method = "GET"
          uri = "@{body('Extract_Document_Text')['Operation-Location']}"
          headers = {
            "Ocp-Apim-Subscription-Key" = "@parameters('documentIntelligenceKey')"
          }
        }
        runAfter = {
          "Wait_for_Analysis" = ["Succeeded"]
        }
      }
      
      "Process_Each_Language" = {
        type = "Foreach"
        foreach = "@parameters('targetLanguages')"
        actions = {
          "Translate_Document_Text" = {
            type = "Http"
            inputs = {
              method = "POST"
              uri = "@{parameters('translatorEndpoint')}/translator/text/v3.0/translate"
              headers = {
                "Ocp-Apim-Subscription-Key" = "@parameters('translatorKey')"
                "Content-Type" = "application/json"
              }
              body = [{
                text = "@{body('Get_Analysis_Results')['analyzeResult']['content']}"
              }]
              queries = {
                "api-version" = "3.0"
                to = "@item()"
              }
            }
          }
          
          "Create_Translated_Document" = {
            type = "ApiConnection"
            inputs = {
              host = {
                connection = {
                  name = "@parameters('$connections')['azureblob']['connectionId']"
                }
              }
              method = "post"
              path = "/datasets/default/files"
              queries = {
                folderPath = "/localized-output"
                name = "@{replace(triggerBody()['Name'], '.', concat('-', item(), '.'))}"
              }
              body = "@{first(body('Translate_Document_Text'))['translations'][0]['text']}"
            }
            runAfter = {
              "Translate_Document_Text" = ["Succeeded"]
            }
          }
        }
        runAfter = {
          "Get_Analysis_Results" = ["Succeeded"]
        }
      }
      
      "Log_Processing_Complete" = {
        type = "ApiConnection"
        inputs = {
          host = {
            connection = {
              name = "@parameters('$connections')['azureblob']['connectionId']"
            }
          }
          method = "post"
          path = "/datasets/default/files"
          queries = {
            folderPath = "/workflow-logs"
            name = "@{concat('completed-', formatDateTime(utcNow(), 'yyyyMMdd-HHmmss'), '.log')}"
          }
          body = "@{concat('Processing completed for: ', triggerBody()['Name'], ' at ', utcNow(), '. Languages: ', join(parameters('targetLanguages'), ', '))}"
        }
        runAfter = {
          "Process_Each_Language" = ["Succeeded"]
        }
      }
    }
    
    outputs = {}
  })
  
  # Configure workflow parameters with service connections
  workflow_parameters = {
    "$connections" = jsonencode({
      azureblob = {
        connectionId = azurerm_api_connection.blob_storage.id
        connectionName = azurerm_api_connection.blob_storage.name
        id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.localization.location}/managedApis/azureblob"
      }
    })
  }
  
  tags = var.tags
}

# Create diagnostic settings for monitoring (if enabled)
resource "azurerm_monitor_diagnostic_setting" "translator" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-translator-${random_string.suffix.result}"
  target_resource_id = azurerm_cognitive_account.translator.id
  storage_account_id = azurerm_storage_account.documents.id
  
  log_analytics_workspace_id = var.enable_monitoring ? azurerm_log_analytics_workspace.localization[0].id : null
  
  enabled_log {
    category = "Audit"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "RequestResponse"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  metric {
    category = "AllMetrics"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "document_intelligence" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-doc-intel-${random_string.suffix.result}"
  target_resource_id = azurerm_cognitive_account.document_intelligence.id
  storage_account_id = azurerm_storage_account.documents.id
  
  log_analytics_workspace_id = var.enable_monitoring ? azurerm_log_analytics_workspace.localization[0].id : null
  
  enabled_log {
    category = "Audit"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "RequestResponse"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  metric {
    category = "AllMetrics"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Create Log Analytics Workspace for monitoring (if enabled)
resource "azurerm_log_analytics_workspace" "localization" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.localization.name
  location            = azurerm_resource_group.localization.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = var.tags
}

# Create action group for alerts (if monitoring enabled)
resource "azurerm_monitor_action_group" "localization" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ag-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.localization.name
  short_name          = "localization"
  
  tags = var.tags
}

# Create metric alert for high translation API usage
resource "azurerm_monitor_metric_alert" "translator_high_usage" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "alert-translator-high-usage-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.localization.name
  scopes              = [azurerm_cognitive_account.translator.id]
  description         = "Alert when translator API usage is high"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "TotalCalls"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 1000
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.localization[0].id
  }
  
  tags = var.tags
}

# Create metric alert for document intelligence errors
resource "azurerm_monitor_metric_alert" "document_intelligence_errors" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "alert-doc-intel-errors-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.localization.name
  scopes              = [azurerm_cognitive_account.document_intelligence.id]
  description         = "Alert when document intelligence has high error rate"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "Errors"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.localization[0].id
  }
  
  tags = var.tags
}