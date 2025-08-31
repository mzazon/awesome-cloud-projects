# Main Terraform configuration for Event-Driven AI Agent Workflows
# Creates AI Foundry hub, project, Service Bus, and Logic Apps infrastructure

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and tagging
locals {
  suffix = random_string.suffix.result
  
  # Generate resource names with suffix if not provided
  ai_foundry_hub_name     = var.ai_foundry_hub_name != "" ? var.ai_foundry_hub_name : "aihub-${var.project_name}-${local.suffix}"
  ai_foundry_project_name = var.ai_foundry_project_name != "" ? var.ai_foundry_project_name : "aiproject-${var.project_name}-${local.suffix}"
  service_bus_namespace   = "sb-${var.project_name}-${local.suffix}"
  logic_app_name         = var.logic_app_name != "" ? var.logic_app_name : "la-${var.project_name}-${local.suffix}"
  
  # Common tags for all resources
  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "recipe"
    ManagedBy   = "terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  }, var.tags)
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Create or reference existing resource group
resource "azurerm_resource_group" "main" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

locals {
  resource_group = var.create_resource_group ? azurerm_resource_group.main[0] : data.azurerm_resource_group.existing[0]
}

# Log Analytics Workspace for diagnostic logging
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_diagnostic_logs ? 1 : 0
  name                = "law-${var.project_name}-${local.suffix}"
  location            = local.resource_group.location
  resource_group_name = local.resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project_name}-${local.suffix}"
  location            = local.resource_group.location
  resource_group_name = local.resource_group.name
  workspace_id        = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].id : null
  application_type    = "web"
  tags                = local.common_tags
}

# Key Vault for storing secrets and connection strings
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${local.suffix}"
  location            = local.resource_group.location
  resource_group_name = local.resource_group.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Enable access for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Get", "List", "Create", "Delete", "Update", "Recover", "Purge"
    ]
    
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Purge"
    ]
    
    certificate_permissions = [
      "Get", "List", "Create", "Delete", "Update", "ManageContacts", "ManageIssuers"
    ]
  }
  
  # Enable soft delete and purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false  # Set to true for production
  
  tags = local.common_tags
}

# Storage Account for AI Foundry workspace
resource "azurerm_storage_account" "ai_foundry" {
  name                     = "st${replace(var.project_name, "-", "")}${local.suffix}"
  resource_group_name      = local.resource_group.name
  location                 = local.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob versioning and change feed
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Enable soft delete for blobs
    delete_retention_policy {
      days = 7
    }
    
    # Enable soft delete for containers
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Container Registry for AI models and images
resource "azurerm_container_registry" "main" {
  name                = "cr${replace(var.project_name, "-", "")}${local.suffix}"
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  sku                 = "Basic"
  admin_enabled       = true
  
  tags = local.common_tags
}

# AI Foundry Hub (Machine Learning Workspace acting as Hub)
resource "azurerm_machine_learning_workspace" "hub" {
  name                          = local.ai_foundry_hub_name
  location                      = local.resource_group.location
  resource_group_name           = local.resource_group.name
  application_insights_id       = azurerm_application_insights.main.id
  key_vault_id                  = azurerm_key_vault.main.id
  storage_account_id            = azurerm_storage_account.ai_foundry.id
  container_registry_id         = azurerm_container_registry.main.id
  
  # Configure as AI Foundry Hub
  kind        = "Hub"
  description = "AI Foundry Hub for intelligent event-driven workflows"
  
  # Identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  # Public network access (set to Disabled for production)
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# AI Foundry Project (Machine Learning Workspace acting as Project)
resource "azurerm_machine_learning_workspace" "project" {
  name                          = local.ai_foundry_project_name
  location                      = local.resource_group.location
  resource_group_name           = local.resource_group.name
  application_insights_id       = azurerm_application_insights.main.id
  key_vault_id                  = azurerm_key_vault.main.id
  storage_account_id            = azurerm_storage_account.ai_foundry.id
  container_registry_id         = azurerm_container_registry.main.id
  
  # Configure as AI Foundry Project with hub reference
  kind        = "Project"
  description = "AI Foundry Project for business event processing agents"
  
  # Link to the hub workspace
  # Note: This uses azapi as the azurerm provider doesn't fully support hub-project relationship yet
  depends_on = [azurerm_machine_learning_workspace.hub]
  
  # Identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  # Public network access (set to Disabled for production)
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# Service Bus Namespace for event messaging
resource "azurerm_servicebus_namespace" "main" {
  name                = local.service_bus_namespace
  location            = local.resource_group.location
  resource_group_name = local.resource_group.name
  sku                 = var.service_bus_sku
  
  # Enable zone redundancy for Premium SKU
  zone_redundant = var.service_bus_sku == "Premium" ? true : false
  
  tags = local.common_tags
}

# Service Bus Queue for event processing
resource "azurerm_servicebus_queue" "event_processing" {
  name         = "event-processing-queue"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Queue configuration
  max_size_in_megabytes                = var.service_bus_queue_max_size
  default_message_ttl                  = var.service_bus_message_ttl
  duplicate_detection_history_time_window = "PT10M"
  
  # Enable duplicate detection
  requires_duplicate_detection = true
  
  # Dead lettering configuration
  dead_lettering_on_message_expiration = true
  max_delivery_count                   = 10
  
  # Enable sessions for ordered processing
  requires_session = false
}

# Service Bus Topic for event distribution
resource "azurerm_servicebus_topic" "business_events" {
  name         = "business-events-topic"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Topic configuration
  max_size_in_megabytes       = var.service_bus_queue_max_size
  default_message_ttl         = var.service_bus_message_ttl
  enable_partitioning         = var.service_bus_topic_enable_partitioning
  requires_duplicate_detection = true
  
  # Duplicate detection window
  duplicate_detection_history_time_window = "PT10M"
}

# Service Bus Topic Subscription for AI agent processing
resource "azurerm_servicebus_subscription" "ai_agent" {
  name     = "ai-agent-subscription"
  topic_id = azurerm_servicebus_topic.business_events.id
  
  # Subscription configuration
  max_delivery_count                = 10
  dead_lettering_on_message_expiration = true
  dead_lettering_on_filter_evaluation_error = true
  
  # Auto-delete configuration
  auto_delete_on_idle = "P14D"  # 14 days
}

# Service Bus Authorization Rule for Logic Apps access
resource "azurerm_servicebus_namespace_authorization_rule" "logic_app_access" {
  name         = "LogicAppAccess"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Permissions for Logic Apps
  listen = true
  send   = true
  manage = false
}

# Store Service Bus connection string in Key Vault
resource "azurerm_key_vault_secret" "service_bus_connection" {
  name         = "service-bus-connection-string"
  value        = azurerm_servicebus_namespace_authorization_rule.logic_app_access.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
}

# API Connection for Service Bus in Logic Apps
resource "azurerm_api_connection" "service_bus" {
  name                = "servicebus-connection"
  resource_group_name = local.resource_group.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${local.resource_group.location}/managedApis/servicebus"
  
  parameter_values = {
    connectionString = azurerm_servicebus_namespace_authorization_rule.logic_app_access.primary_connection_string
  }
  
  tags = local.common_tags
}

# Logic App Workflow for event processing
resource "azurerm_logic_app_workflow" "main" {
  name                = local.logic_app_name
  location            = local.resource_group.location
  resource_group_name = local.resource_group.name
  
  # Workflow definition with Service Bus trigger
  workflow_schema   = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"
  
  parameters = {
    "$connections" = {
      defaultValue = {}
      type         = "Object"
    }
  }
  
  tags = local.common_tags
}

# Update Logic App workflow with proper connections
resource "azurerm_template_deployment" "logic_app_definition" {
  name                = "logic-app-definition-${local.suffix}"
  resource_group_name = local.resource_group.name
  deployment_mode     = "Incremental"
  
  template_body = jsonencode({
    "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {}
    resources = [
      {
        type = "Microsoft.Logic/workflows"
        apiVersion = "2019-05-01"
        name = azurerm_logic_app_workflow.main.name
        location = local.resource_group.location
        properties = {
          definition = {
            "$schema" = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
            contentVersion = "1.0.0.0"
            parameters = {
              "$connections" = {
                defaultValue = {}
                type = "Object"
              }
            }
            triggers = {
              "When_a_message_is_received_in_a_queue" = {
                type = "ApiConnection"
                inputs = {
                  host = {
                    connection = {
                      name = "@parameters('$connections')['servicebus']['connectionId']"
                    }
                  }
                  method = "get"
                  path = "/@{encodeURIComponent(encodeURIComponent('event-processing-queue'))}/messages/head"
                  queries = {
                    queueType = "Main"
                  }
                }
                recurrence = {
                  frequency = var.logic_app_trigger_frequency
                  interval = var.logic_app_trigger_interval
                }
              }
            }
            actions = {
              "Initialize_variable_EventData" = {
                type = "InitializeVariable"
                inputs = {
                  variables = [
                    {
                      name = "EventData"
                      type = "object"
                      value = "@json(base64ToString(triggerBody()?['ContentData']))"
                    }
                  ]
                }
              }
              "Parse_Event_Content" = {
                type = "ParseJson"
                inputs = {
                  content = "@variables('EventData')"
                  schema = {
                    type = "object"
                    properties = {
                      eventType = { type = "string" }
                      content = { type = "string" }
                      metadata = { type = "object" }
                    }
                  }
                }
                runAfter = {
                  "Initialize_variable_EventData" = ["Succeeded"]
                }
              }
              "Condition_Check_Event_Type" = {
                type = "If"
                expression = {
                  and = [
                    {
                      not = {
                        equals = [
                          "@body('Parse_Event_Content')?['eventType']",
                          "@null"
                        ]
                      }
                    }
                  ]
                }
                actions = {
                  "HTTP_Call_to_AI_Agent" = {
                    type = "Http"
                    inputs = {
                      method = "POST"
                      uri = "https://example.com/ai-agent/process"
                      headers = {
                        "Content-Type" = "application/json"
                        "Authorization" = "Bearer @{parameters('ai-agent-token')}"
                      }
                      body = {
                        eventData = "@body('Parse_Event_Content')"
                        timestamp = "@utcNow()"
                        workspaceId = azurerm_machine_learning_workspace.project.id
                      }
                    }
                  }
                  "Log_Processing_Success" = {
                    type = "Compose"
                    inputs = {
                      status = "success"
                      eventType = "@body('Parse_Event_Content')?['eventType']"
                      processedAt = "@utcNow()"
                      response = "@body('HTTP_Call_to_AI_Agent')"
                    }
                    runAfter = {
                      "HTTP_Call_to_AI_Agent" = ["Succeeded"]
                    }
                  }
                }
                else = {
                  actions = {
                    "Log_Invalid_Event" = {
                      type = "Compose"
                      inputs = {
                        status = "error"
                        message = "Invalid event format or missing eventType"
                        eventData = "@variables('EventData')"
                        timestamp = "@utcNow()"
                      }
                    }
                  }
                }
                runAfter = {
                  "Parse_Event_Content" = ["Succeeded"]
                }
              }
            }
          }
          parameters = {
            "$connections" = {
              value = {
                servicebus = {
                  connectionId = azurerm_api_connection.service_bus.id
                  connectionName = azurerm_api_connection.service_bus.name
                  id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${local.resource_group.location}/managedApis/servicebus"
                }
              }
            }
          }
        }
      }
    ]
  })
  
  depends_on = [
    azurerm_logic_app_workflow.main,
    azurerm_api_connection.service_bus,
    azurerm_servicebus_queue.event_processing
  ]
}

# Diagnostic settings for Service Bus
resource "azurerm_monitor_diagnostic_setting" "service_bus" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-${azurerm_servicebus_namespace.main.name}"
  target_resource_id = azurerm_servicebus_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable all available log categories
  enabled_log {
    category = "OperationalLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Logic App
resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-${azurerm_logic_app_workflow.main.name}"
  target_resource_id = azurerm_logic_app_workflow.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable Logic App logs
  enabled_log {
    category = "WorkflowRuntime"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for AI Foundry Hub
resource "azurerm_monitor_diagnostic_setting" "ai_foundry_hub" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-${azurerm_machine_learning_workspace.hub.name}"
  target_resource_id = azurerm_machine_learning_workspace.hub.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable Machine Learning workspace logs
  enabled_log {
    category = "AmlComputeClusterEvent"
  }
  
  enabled_log {
    category = "AmlComputeJobEvent"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}