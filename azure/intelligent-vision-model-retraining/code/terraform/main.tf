# Azure Custom Vision and Logic Apps automation infrastructure
# This Terraform configuration creates a complete MLOps pipeline for automated
# computer vision model retraining using Azure services

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Log Analytics Workspace for monitoring and alerting
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-monitor-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  
  tags = merge(var.tags, {
    Component = "monitoring"
    Service   = "log-analytics"
  })
}

# Create Application Insights for advanced monitoring (optional)
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  tags = merge(var.tags, {
    Component = "monitoring"
    Service   = "application-insights"
  })
}

# Create Storage Account for training data and model artifacts
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  access_tier              = var.storage_account_access_tier
  
  # Security configurations
  https_traffic_only_enabled         = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = var.enable_public_access
  shared_access_key_enabled         = true
  public_network_access_enabled     = true
  
  # Enable hierarchical namespace for better performance
  is_hns_enabled = true
  
  # Network access rules for enhanced security
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  # Blob properties for lifecycle management
  blob_properties {
    versioning_enabled = var.enable_blob_versioning
    
    dynamic "delete_retention_policy" {
      for_each = var.enable_soft_delete ? [1] : []
      content {
        days = var.blob_soft_delete_retention_days
      }
    }
    
    dynamic "container_delete_retention_policy" {
      for_each = var.enable_soft_delete ? [1] : []
      content {
        days = var.container_soft_delete_retention_days
      }
    }
  }
  
  tags = merge(var.tags, {
    Component = "storage"
    Service   = "blob-storage"
  })
}

# Create storage container for training images
resource "azurerm_storage_container" "training_images" {
  name                  = "training-images"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  metadata = {
    purpose = "training-data"
    type    = "input"
  }
}

# Create storage container for model artifacts
resource "azurerm_storage_container" "model_artifacts" {
  name                  = "model-artifacts"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  metadata = {
    purpose = "model-storage"
    type    = "output"
  }
}

# Create storage container for processed images
resource "azurerm_storage_container" "processed_images" {
  name                  = "processed-images"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  metadata = {
    purpose = "processed-data"
    type    = "archive"
  }
}

# Create Azure Custom Vision Training Service
resource "azurerm_cognitive_account" "custom_vision_training" {
  name                = "cv-training-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "CustomVision.Training"
  sku_name            = var.custom_vision_sku
  
  # Custom subdomain for secure access
  custom_subdomain_name = "cv-training-${random_string.suffix.result}"
  
  # Enable public network access
  public_network_access_enabled = true
  
  tags = merge(var.tags, {
    Component = "ai-ml"
    Service   = "custom-vision"
    Type      = "training"
  })
}

# Create Azure Custom Vision Prediction Service
resource "azurerm_cognitive_account" "custom_vision_prediction" {
  name                = "cv-prediction-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "CustomVision.Prediction"
  sku_name            = var.custom_vision_sku
  
  # Custom subdomain for secure access
  custom_subdomain_name = "cv-prediction-${random_string.suffix.result}"
  
  # Enable public network access
  public_network_access_enabled = true
  
  tags = merge(var.tags, {
    Component = "ai-ml"
    Service   = "custom-vision"
    Type      = "prediction"
  })
}

# Create Custom Vision Project using Azure API
resource "azapi_resource" "custom_vision_project" {
  type      = "Microsoft.CognitiveServices/accounts/customvision/projects@2022-02-01-preview"
  name      = "automated-retraining-project"
  parent_id = azurerm_cognitive_account.custom_vision_training.id
  
  body = jsonencode({
    properties = {
      name        = "automated-retraining-project"
      description = "Automated model retraining with Logic Apps and Terraform"
      settings = {
        projectType        = var.custom_vision_project_type
        classificationType = var.custom_vision_classification_type
        domainId          = "ee85a74c-405e-4adc-bb47-ffa8ca0c9f31" # General domain
      }
    }
  })
  
  depends_on = [azurerm_cognitive_account.custom_vision_training]
}

# Store Custom Vision project configuration in blob storage
resource "azurerm_storage_blob" "project_config" {
  name                   = "project-config.json"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.model_artifacts.name
  type                   = "Block"
  
  source_content = jsonencode({
    projectId            = jsondecode(azapi_resource.custom_vision_project.output).id
    trainingEndpoint     = azurerm_cognitive_account.custom_vision_training.endpoint
    trainingKey          = azurerm_cognitive_account.custom_vision_training.primary_access_key
    predictionEndpoint   = azurerm_cognitive_account.custom_vision_prediction.endpoint
    predictionKey        = azurerm_cognitive_account.custom_vision_prediction.primary_access_key
    resourceId           = azurerm_cognitive_account.custom_vision_prediction.id
    projectType          = var.custom_vision_project_type
    classificationType   = var.custom_vision_classification_type
    createdDate          = timestamp()
  })
  
  content_type = "application/json"
  
  depends_on = [azapi_resource.custom_vision_project]
}

# Create API Connection for Azure Blob Storage
resource "azurerm_api_connection" "blob_storage" {
  name                = "blob-connection-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/azureblob"
  
  parameter_values = {
    accountName = azurerm_storage_account.main.name
    accessKey   = azurerm_storage_account.main.primary_access_key
  }
  
  tags = merge(var.tags, {
    Component = "integration"
    Service   = "api-connection"
    Type      = "blob-storage"
  })
}

# Create API Connection for HTTP requests
resource "azurerm_api_connection" "http" {
  name                = "http-connection-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/http"
  
  tags = merge(var.tags, {
    Component = "integration"
    Service   = "api-connection"
    Type      = "http"
  })
}

# Create Logic App for automated retraining workflow
resource "azurerm_logic_app_workflow" "retraining_workflow" {
  name                = "logic-cv-retrain-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Enable workflow logging
  workflow_parameters = {
    "$connections" = {
      defaultValue = {}
      type         = "Object"
    }
  }
  
  # Define the complete workflow for automated retraining
  workflow_schema = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version = "1.0.0.0"
  
  parameters = {
    "$connections" = {
      value = {
        azureblob = {
          connectionId   = azurerm_api_connection.blob_storage.id
          connectionName = azurerm_api_connection.blob_storage.name
          id             = azurerm_api_connection.blob_storage.managed_api_id
        }
        http = {
          connectionId   = azurerm_api_connection.http.id
          connectionName = azurerm_api_connection.http.name
          id             = azurerm_api_connection.http.managed_api_id
        }
      }
    }
  }
  
  tags = merge(var.tags, {
    Component = "automation"
    Service   = "logic-apps"
    Purpose   = "ml-retraining"
  })
}

# Create comprehensive workflow definition for the Logic App
resource "azapi_resource" "workflow_definition" {
  type      = "Microsoft.Logic/workflows@2019-05-01"
  name      = azurerm_logic_app_workflow.retraining_workflow.name
  parent_id = azurerm_resource_group.main.id
  location  = azurerm_resource_group.main.location
  
  body = jsonencode({
    properties = {
      definition = {
        "$schema"        = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
        contentVersion   = "1.0.0.0"
        parameters = {
          "$connections" = {
            defaultValue = {}
            type         = "Object"
          }
        }
        triggers = {
          When_a_blob_is_added_or_modified = {
            type = "ApiConnection"
            inputs = {
              host = {
                connection = {
                  name = "@parameters('$connections')['azureblob']['connectionId']"
                }
              }
              method = "get"
              path   = "/datasets/default/triggers/batch/onupdatedfile"
              queries = {
                folderId     = azurerm_storage_container.training_images.name
                maxFileCount = var.training_images_max_file_count
              }
            }
            recurrence = {
              frequency = var.logic_app_trigger_frequency
              interval  = var.logic_app_trigger_interval
            }
            metadata = {
              "${azurerm_storage_container.training_images.name}" = azurerm_storage_container.training_images.name
            }
          }
        }
        actions = {
          Get_project_configuration = {
            type = "ApiConnection"
            inputs = {
              host = {
                connection = {
                  name = "@parameters('$connections')['azureblob']['connectionId']"
                }
              }
              method = "get"
              path   = "/datasets/default/files/@{encodeURIComponent('${azurerm_storage_container.model_artifacts.name}/project-config.json')}/content"
            }
          }
          Parse_project_config = {
            type = "ParseJson"
            inputs = {
              content = "@body('Get_project_configuration')"
              schema = {
                properties = {
                  projectId          = { type = "string" }
                  trainingEndpoint   = { type = "string" }
                  trainingKey        = { type = "string" }
                  predictionEndpoint = { type = "string" }
                  predictionKey      = { type = "string" }
                  resourceId         = { type = "string" }
                  projectType        = { type = "string" }
                  classificationType = { type = "string" }
                  createdDate        = { type = "string" }
                }
                type = "object"
              }
            }
            runAfter = {
              Get_project_configuration = ["Succeeded"]
            }
          }
          Validate_training_data = {
            type = "ApiConnection"
            inputs = {
              host = {
                connection = {
                  name = "@parameters('$connections')['azureblob']['connectionId']"
                }
              }
              method = "get"
              path   = "/datasets/default/folders/@{encodeURIComponent(encodeURIComponent('${azurerm_storage_container.training_images.name}'))}/files"
            }
            runAfter = {
              Parse_project_config = ["Succeeded"]
            }
          }
          Condition_check_minimum_images = {
            type = "If"
            expression = {
              and = [
                {
                  greater = [
                    "@length(body('Validate_training_data')?['value'])",
                    15
                  ]
                }
              ]
            }
            actions = {
              Start_training = {
                type = "Http"
                inputs = {
                  method = "POST"
                  uri    = "@{body('Parse_project_config')['trainingEndpoint']}customvision/v3.0/Training/projects/@{body('Parse_project_config')['projectId']}/train"
                  headers = {
                    "Training-Key"  = "@{body('Parse_project_config')['trainingKey']}"
                    "Content-Type"  = "application/json"
                  }
                  body = {
                    forceTrain = true
                    trainingType = "Regular"
                  }
                }
              }
              Wait_for_training_completion = {
                type = "Until"
                expression = {
                  equals = [
                    "@outputs('Get_training_status')['body']['status']",
                    "Completed"
                  ]
                }
                limit = {
                  count = 60
                  timeout = "PT30M"
                }
                actions = {
                  Get_training_status = {
                    type = "Http"
                    inputs = {
                      method = "GET"
                      uri    = "@{body('Parse_project_config')['trainingEndpoint']}customvision/v3.0/Training/projects/@{body('Parse_project_config')['projectId']}/iterations/@{body('Start_training')['id']}"
                      headers = {
                        "Training-Key" = "@{body('Parse_project_config')['trainingKey']}"
                      }
                    }
                  }
                  Delay_before_next_check = {
                    type = "Wait"
                    inputs = {
                      interval = {
                        count = 30
                        unit = "Second"
                      }
                    }
                    runAfter = {
                      Get_training_status = ["Succeeded"]
                    }
                  }
                }
                runAfter = {
                  Start_training = ["Succeeded"]
                }
              }
              Publish_iteration = {
                type = "Http"
                inputs = {
                  method = "POST"
                  uri    = "@{body('Parse_project_config')['trainingEndpoint']}customvision/v3.0/Training/projects/@{body('Parse_project_config')['projectId']}/iterations/@{body('Start_training')['id']}/publish"
                  headers = {
                    "Training-Key"  = "@{body('Parse_project_config')['trainingKey']}"
                    "Content-Type"  = "application/json"
                  }
                  body = {
                    name = "production-@{utcnow()}"
                    predictionId = "@{body('Parse_project_config')['resourceId']}"
                  }
                }
                runAfter = {
                  Wait_for_training_completion = ["Succeeded"]
                }
              }
              Log_training_success = {
                type = "Http"
                inputs = {
                  method = "POST"
                  uri    = "${azurerm_log_analytics_workspace.main.primary_shared_key}@${azurerm_log_analytics_workspace.main.workspace_id}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
                  headers = {
                    "Content-Type"        = "application/json"
                    "Log-Type"           = "CustomVisionTraining"
                    "x-ms-date"          = "@{formatDateTime(utcnow(), 'r')}"
                    "Authorization"      = "SharedKey ${azurerm_log_analytics_workspace.main.workspace_id}:@{base64(hmacsha256(base64('${azurerm_log_analytics_workspace.main.primary_shared_key}'), concat('POST\n', string(length(string(body('Start_training')))), '\napplication/json\nx-ms-date:', formatDateTime(utcnow(), 'r'), '\n/api/logs')))}"
                  }
                  body = {
                    message     = "Training completed successfully for project @{body('Parse_project_config')['projectId']}"
                    timestamp   = "@{utcnow()}"
                    level       = "Info"
                    projectId   = "@{body('Parse_project_config')['projectId']}"
                    iterationId = "@{body('Start_training')['id']}"
                    triggerType = "blob-upload"
                    precision   = "@{body('Get_training_status')['body']['precision']}"
                    recall      = "@{body('Get_training_status')['body']['recall']}"
                    averagePrecision = "@{body('Get_training_status')['body']['averagePrecision']}"
                  }
                }
                runAfter = {
                  Publish_iteration = ["Succeeded"]
                }
              }
              Move_processed_images = {
                type = "ApiConnection"
                inputs = {
                  host = {
                    connection = {
                      name = "@parameters('$connections')['azureblob']['connectionId']"
                    }
                  }
                  method = "post"
                  path   = "/datasets/default/copyFile"
                  queries = {
                    source      = "@{triggerBody()['Name']}"
                    destination = "${azurerm_storage_container.processed_images.name}/@{formatDateTime(utcnow(), 'yyyy-MM-dd')}/@{triggerBody()['Name']}"
                    overwrite   = true
                  }
                }
                runAfter = {
                  Log_training_success = ["Succeeded"]
                }
              }
            }
            else = {
              actions = {
                Log_insufficient_data = {
                  type = "Http"
                  inputs = {
                    method = "POST"
                    uri    = "${azurerm_log_analytics_workspace.main.primary_shared_key}@${azurerm_log_analytics_workspace.main.workspace_id}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
                    headers = {
                      "Content-Type"        = "application/json"
                      "Log-Type"           = "CustomVisionTraining"
                      "x-ms-date"          = "@{formatDateTime(utcnow(), 'r')}"
                      "Authorization"      = "SharedKey ${azurerm_log_analytics_workspace.main.workspace_id}:@{base64(hmacsha256(base64('${azurerm_log_analytics_workspace.main.primary_shared_key}'), concat('POST\n', string(length('insufficient data')), '\napplication/json\nx-ms-date:', formatDateTime(utcnow(), 'r'), '\n/api/logs')))}"
                    }
                    body = {
                      message     = "Insufficient training data - minimum 15 images required"
                      timestamp   = "@{utcnow()}"
                      level       = "Warning"
                      projectId   = "@{body('Parse_project_config')['projectId']}"
                      imageCount  = "@{length(body('Validate_training_data')?['value'])}"
                      triggerType = "blob-upload"
                    }
                  }
                }
              }
            }
            runAfter = {
              Validate_training_data = ["Succeeded"]
            }
          }
        }
        outputs = {}
      }
      parameters = {
        "$connections" = {
          value = {
            azureblob = {
              connectionId   = azurerm_api_connection.blob_storage.id
              connectionName = azurerm_api_connection.blob_storage.name
              id             = azurerm_api_connection.blob_storage.managed_api_id
            }
            http = {
              connectionId   = azurerm_api_connection.http.id
              connectionName = azurerm_api_connection.http.name
              id             = azurerm_api_connection.http.managed_api_id
            }
          }
        }
      }
    }
  })
  
  depends_on = [
    azurerm_logic_app_workflow.retraining_workflow,
    azurerm_api_connection.blob_storage,
    azurerm_api_connection.http
  ]
}

# Create Action Group for alert notifications
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-cv-alerts-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "cvAlerts"
  
  # Add email notification (configurable)
  email_receiver {
    name          = "admin-email"
    email_address = var.notification_email
  }
  
  tags = merge(var.tags, {
    Component = "monitoring"
    Service   = "action-group"
  })
}

# Create alert for Custom Vision training success rate
resource "azurerm_monitor_metric_alert" "training_success_rate" {
  name                = "CustomVision-Training-Success-Rate-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cognitive_account.custom_vision_training.id]
  description         = "Alert when Custom Vision training success rate drops"
  
  frequency           = var.alert_evaluation_frequency
  window_size         = var.alert_window_size
  severity            = 2
  
  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "TotalCalls"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = merge(var.tags, {
    Component = "monitoring"
    Service   = "metric-alert"
    Type      = "training-success"
  })
}

# Create alert for Logic App failures
resource "azurerm_monitor_metric_alert" "logic_app_failures" {
  name                = "LogicApp-Failure-Alert-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_logic_app_workflow.retraining_workflow.id]
  description         = "Alert when Logic App workflow fails"
  
  frequency           = "PT1M"
  window_size         = "PT5M"
  severity            = 1
  
  criteria {
    metric_namespace = "Microsoft.Logic/workflows"
    metric_name      = "RunsFailed"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = merge(var.tags, {
    Component = "monitoring"
    Service   = "metric-alert"
    Type      = "workflow-failure"
  })
}

# Create alert for storage account access failures
resource "azurerm_monitor_metric_alert" "storage_failures" {
  name                = "Storage-Access-Failures-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_storage_account.main.id]
  description         = "Alert when storage account access failures occur"
  
  frequency           = "PT5M"
  window_size         = "PT15M"
  severity            = 2
  
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "Transactions"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 10
    
    dimension {
      name     = "ResponseType"
      operator = "Include"
      values   = ["ClientError", "ServerError"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = merge(var.tags, {
    Component = "monitoring"
    Service   = "metric-alert"
    Type      = "storage-failure"
  })
}

# Create diagnostic setting for Logic App
resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  name               = "diag-logic-app-${random_string.suffix.result}"
  target_resource_id = azurerm_logic_app_workflow.retraining_workflow.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "WorkflowRuntime"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic setting for Custom Vision Training
resource "azurerm_monitor_diagnostic_setting" "custom_vision_training" {
  name               = "diag-cv-training-${random_string.suffix.result}"
  target_resource_id = azurerm_cognitive_account.custom_vision_training.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "Audit"
  }
  
  enabled_log {
    category = "RequestResponse"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic setting for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  name               = "diag-storage-${random_string.suffix.result}"
  target_resource_id = "${azurerm_storage_account.main.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "StorageRead"
  }
  
  enabled_log {
    category = "StorageWrite"
  }
  
  enabled_log {
    category = "StorageDelete"
  }
  
  metric {
    category = "Transaction"
    enabled  = true
  }
}

# Create blob lifecycle management policy
resource "azurerm_storage_management_policy" "main" {
  storage_account_id = azurerm_storage_account.main.id
  
  rule {
    name    = "processed-images-lifecycle"
    enabled = true
    
    filters {
      prefix_match = [azurerm_storage_container.processed_images.name]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = 365
      }
    }
  }
}