# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Local values for consistent naming and tagging
locals {
  # Common resource naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_string.suffix.result
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      Purpose     = "content-moderation"
      ManagedBy   = "terraform"
      CreatedDate = formatdate("YYYY-MM-DD", timestamp())
    },
    var.tags
  )

  # Content Safety custom subdomain (generated if not provided)
  content_safety_subdomain = var.content_safety_custom_subdomain != "" ? var.content_safety_custom_subdomain : "cs-${local.name_prefix}-${local.name_suffix}"
}

# Resource Group for all content moderation resources
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${local.name_suffix}"
  location = var.location
  tags     = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Azure AI Content Safety Service for content analysis
resource "azurerm_cognitive_account" "content_safety" {
  name                = local.content_safety_subdomain
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "ContentSafety"
  sku_name            = var.content_safety_sku

  # Enable custom subdomain for consistent endpoint URL
  custom_question_answering_search_service_id = null
  fqdns                                       = []
  local_auth_enabled                          = true
  outbound_network_access_restricted          = false
  public_network_access_enabled               = true

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Storage Account for content uploads and processing
resource "azurerm_storage_account" "content_storage" {
  name                = "st${var.project_name}${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Storage configuration
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_account_replication_type
  access_tier              = var.storage_access_tier
  account_kind             = "StorageV2"

  # Security configuration
  enable_https_traffic_only = var.enable_https_only
  min_tls_version          = var.minimum_tls_version
  allow_nested_items_to_be_public = false

  # Network access configuration
  public_network_access_enabled = true
  
  # Advanced threat protection
  infrastructure_encryption_enabled = true

  # Blob storage configuration
  blob_properties {
    # Enable versioning for content audit trail
    versioning_enabled = true
    
    # Enable change feed for event processing
    change_feed_enabled = true
    
    # Retention policy for change feed
    change_feed_retention_in_days = 7

    # Container delete retention policy
    container_delete_retention_policy {
      days = 7
    }

    # Blob delete retention policy
    delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Storage Container for content uploads
resource "azurerm_storage_container" "content_uploads" {
  name                  = var.content_container_name
  storage_account_name  = azurerm_storage_account.content_storage.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.content_storage]
}

# Storage Account Lifecycle Management Policy
resource "azurerm_storage_management_policy" "content_lifecycle" {
  count              = var.enable_lifecycle_management ? 1 : 0
  storage_account_id = azurerm_storage_account.content_storage.id

  rule {
    name    = "content-lifecycle-rule"
    enabled = true
    filters {
      prefix_match = [var.content_container_name]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = var.lifecycle_days_to_cool
        tier_to_archive_after_days_since_modification_greater_than = var.lifecycle_days_to_archive
        delete_after_days_since_modification_greater_than          = 365
      }
      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}

# App Service Plan for Logic App (Consumption plan)
resource "azurerm_service_plan" "logic_app_plan" {
  name                = "asp-${local.name_prefix}-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Windows"
  sku_name            = var.logic_app_plan_sku

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# API Connection for Azure Blob Storage
resource "azurerm_api_connection" "azureblob" {
  name                = "azureblob-connection-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/azureblob"
  display_name        = "Azure Blob Storage Connection"

  parameter_values = {
    connectionString = azurerm_storage_account.content_storage.primary_connection_string
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"], parameter_values]
  }
}

# Logic App for Content Moderation Workflow
resource "azurerm_logic_app_workflow" "content_moderation" {
  name                = "la-${local.name_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Enable or disable the workflow based on variable
  enabled = var.enable_logic_app

  # Workflow definition with content moderation logic
  workflow_schema        = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version       = "1.0.0.0"
  
  # Define workflow parameters for connections
  parameters = {
    "$connections" = jsonencode({
      defaultValue = {}
      type         = "Object"
    })
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags["CreatedDate"]]
  }
}

# Workflow Definition - stored separately for better readability
locals {
  workflow_definition = jsonencode({
    triggers = {
      "When_a_blob_is_added_or_modified" = {
        recurrence = {
          frequency = "Minute"
          interval  = 1
        }
        splitOn = "@triggerBody()"
        type    = "ApiConnection"
        inputs = {
          host = {
            connection = {
              name = "@parameters('$connections')['azureblob']['connectionId']"
            }
          }
          method = "get"
          path   = "/datasets/default/triggers/batch/onupdatedfile"
          queries = {
            folderId     = var.content_container_name
            maxFileCount = 10
          }
        }
      }
    }
    actions = {
      "Get_blob_content" = {
        runAfter = {}
        type     = "ApiConnection"
        inputs = {
          host = {
            connection = {
              name = "@parameters('$connections')['azureblob']['connectionId']"
            }
          }
          method = "get"
          path   = "/datasets/default/files/@{encodeURIComponent(encodeURIComponent(triggerBody()?['Path']))}/content"
          queries = {
            inferContentType = true
          }
        }
      }
      "Analyze_content_with_AI" = {
        runAfter = {
          "Get_blob_content" = ["Succeeded"]
        }
        type = "Http"
        inputs = {
          body = {
            text       = "@{base64ToString(body('Get_blob_content')?['$content'])}"
            outputType = "FourSeverityLevels"
          }
          headers = {
            "Content-Type"              = "application/json"
            "Ocp-Apim-Subscription-Key" = "@{listKeys('${azurerm_cognitive_account.content_safety.id}', '2023-05-01').key1}"
          }
          method = "POST"
          uri    = "${azurerm_cognitive_account.content_safety.endpoint}/contentsafety/text:analyze?api-version=2024-09-01"
        }
      }
      "Process_moderation_results" = {
        runAfter = {
          "Analyze_content_with_AI" = ["Succeeded"]
        }
        cases = {
          "Low_Risk_Auto_Approve" = {
            case = var.moderation_severity_thresholds.auto_approve_max_severity
            actions = {
              "Log_approval" = {
                type = "Compose"
                inputs = {
                  message          = "Content approved automatically"
                  file            = "@triggerBody()?['Name']"
                  timestamp       = "@utcnow()"
                  moderationResult = "@body('Analyze_content_with_AI')"
                  decision        = "approved"
                }
              }
            }
          }
          "Medium_Risk_Needs_Review" = {
            case = var.moderation_severity_thresholds.review_min_severity
            actions = {
              "Flag_for_review" = {
                type = "Compose"
                inputs = {
                  message          = "Content flagged for human review"
                  file            = "@triggerBody()?['Name']"
                  timestamp       = "@utcnow()"
                  moderationResult = "@body('Analyze_content_with_AI')"
                  decision        = "review_needed"
                }
              }
            }
          }
          "High_Risk_Auto_Reject" = {
            case = var.moderation_severity_thresholds.auto_reject_min_severity
            actions = {
              "Log_rejection" = {
                type = "Compose"
                inputs = {
                  message          = "Content rejected automatically"
                  file            = "@triggerBody()?['Name']"
                  timestamp       = "@utcnow()"
                  moderationResult = "@body('Analyze_content_with_AI')"
                  decision        = "rejected"
                }
              }
            }
          }
        }
        default = {
          actions = {
            "Flag_for_urgent_review" = {
              type = "Compose"
              inputs = {
                message          = "Content flagged for urgent human review"
                file            = "@triggerBody()?['Name']"
                timestamp       = "@utcnow()"
                moderationResult = "@body('Analyze_content_with_AI')"
                decision        = "urgent_review"
              }
            }
          }
        }
        expression = "@max(body('Analyze_content_with_AI')?['categoriesAnalysis']?[0]?['severity'], body('Analyze_content_with_AI')?['categoriesAnalysis']?[1]?['severity'], body('Analyze_content_with_AI')?['categoriesAnalysis']?[2]?['severity'], body('Analyze_content_with_AI')?['categoriesAnalysis']?[3]?['severity'])"
        type       = "Switch"
      }
    }
  })
}

# Update Logic App Workflow with complete definition and connections
resource "azurerm_template_deployment" "logic_app_definition" {
  name                = "logic-app-definition-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  deployment_mode     = "Incremental"

  template_body = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters     = {}
    variables      = {}
    resources = [{
      type       = "Microsoft.Logic/workflows"
      apiVersion = "2019-05-01"
      name       = azurerm_logic_app_workflow.content_moderation.name
      location   = azurerm_resource_group.main.location
      properties = {
        state      = var.enable_logic_app ? "Enabled" : "Disabled"
        definition = jsondecode(local.workflow_definition)
        parameters = {
          "$connections" = {
            value = {
              azureblob = {
                connectionId   = azurerm_api_connection.azureblob.id
                connectionName = azurerm_api_connection.azureblob.name
                id            = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/azureblob"
              }
            }
          }
        }
      }
    }]
  })

  depends_on = [
    azurerm_logic_app_workflow.content_moderation,
    azurerm_api_connection.azureblob,
    azurerm_cognitive_account.content_safety,
    azurerm_storage_account.content_storage
  ]
}

# Optional: Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  count              = var.enable_storage_logging ? 1 : 0
  name               = "storage-diagnostics-${local.name_suffix}"
  target_resource_id = "${azurerm_storage_account.content_storage.id}/blobServices/default"

  # Send logs to Activity Log (no additional cost)
  enabled_log {
    category = "StorageRead"
  }
  
  enabled_log {
    category = "StorageWrite"
  }
  
  enabled_log {
    category = "StorageDelete"
  }

  # Send metrics
  metric {
    category = "Transaction"
    enabled  = true
  }

  depends_on = [azurerm_storage_account.content_storage]
}