# Main Terraform Configuration for Event-Driven Microservices Choreography
# This file defines all Azure resources required for the choreography pattern implementation
# using Azure Service Bus Premium, Container Apps, Functions, and Monitor Workbooks

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Common tags for all resources
locals {
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      Purpose     = "microservices-choreography"
      ManagedBy   = "terraform"
      CreatedDate = formatdate("YYYY-MM-DD", timestamp())
    },
    var.custom_tags
  )
  
  # Resource naming with consistent pattern
  resource_suffix = random_string.suffix.result
  
  # Service Bus configuration
  service_bus_namespace_name = "sb-${var.project_name}-${local.resource_suffix}"
  
  # Container Apps configuration
  container_environment_name = "cae-${var.project_name}-${local.resource_suffix}"
  
  # Function Apps configuration
  function_storage_name = "stfunc${local.resource_suffix}"
  payment_function_name = "payment-service-${local.resource_suffix}"
  shipping_function_name = "shipping-service-${local.resource_suffix}"
  
  # Monitoring configuration
  log_analytics_name = "log-${var.project_name}-${local.resource_suffix}"
  app_insights_name = "ai-${var.project_name}-${local.resource_suffix}"
}

# Create Azure Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                = var.log_analytics_sku
  retention_in_days  = var.log_analytics_retention_days
  tags               = local.common_tags
}

# Create Application Insights for distributed tracing
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id       = azurerm_log_analytics_workspace.main.id
  application_type   = "web"
  retention_in_days  = 90
  tags               = local.common_tags
}

# Create Azure Service Bus Premium Namespace
resource "azurerm_servicebus_namespace" "main" {
  name                = local.service_bus_namespace_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                = var.service_bus_sku
  capacity           = var.service_bus_sku == "Premium" ? var.service_bus_capacity : null
  
  # Premium-specific features
  zone_redundant = var.enable_zone_redundancy && var.service_bus_sku == "Premium"
  
  tags = local.common_tags
}

# Create Service Bus Topics for event choreography
resource "azurerm_servicebus_topic" "topics" {
  for_each = var.service_bus_topics
  
  name         = each.key
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Topic configuration
  max_message_size_in_kilobytes = each.value.max_message_size_in_kilobytes
  enable_partitioning          = each.value.enable_partitioning
  requires_duplicate_detection = each.value.requires_duplicate_detection
  default_message_ttl          = each.value.default_message_ttl
  auto_delete_on_idle          = each.value.auto_delete_on_idle
  enable_batched_operations    = each.value.enable_batched_operations
  support_ordering            = each.value.support_ordering
}

# Create Service Bus Topic Subscriptions
resource "azurerm_servicebus_subscription" "subscriptions" {
  for_each = var.service_bus_subscriptions
  
  name     = each.key
  topic_id = azurerm_servicebus_topic.topics[each.value.topic_name].id
  
  # Subscription configuration
  max_delivery_count           = each.value.max_delivery_count
  lock_duration               = each.value.lock_duration
  requires_session           = each.value.requires_session
  default_message_ttl         = each.value.default_message_ttl
  auto_delete_on_idle         = each.value.auto_delete_on_idle
  enable_batched_operations   = each.value.enable_batched_operations
  dead_lettering_on_message_expiration = each.value.dead_lettering_on_message_expiration
  dead_lettering_on_filter_evaluation_error = each.value.dead_lettering_on_filter_evaluation_error
}

# Create SQL filter for high-priority orders subscription
resource "azurerm_servicebus_subscription_rule" "high_priority_rule" {
  name            = "HighPriorityRule"
  subscription_id = azurerm_servicebus_subscription.subscriptions["high-priority-orders"].id
  filter_type     = "SqlFilter"
  sql_filter      = "Priority = 'High'"
}

# Create dead letter queue for failed events
resource "azurerm_servicebus_queue" "dead_letter_queue" {
  name         = "failed-events-dlq"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  enable_partitioning                   = false
  max_delivery_count                   = 3
  dead_lettering_on_message_expiration = true
  requires_duplicate_detection         = false
  default_message_ttl                  = "P14D"
  auto_delete_on_idle                  = "P10675199DT2H48M5.4775807S"
  lock_duration                        = "PT1M"
  max_size_in_megabytes               = 1024
}

# Create Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                       = local.container_environment_name
  location                  = azurerm_resource_group.main.location
  resource_group_name       = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  zone_redundancy_enabled   = var.enable_zone_redundancy
  tags                      = local.common_tags
}

# Create Order Service Container App
resource "azurerm_container_app" "order_service" {
  name                         = "order-service"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name         = azurerm_resource_group.main.name
  revision_mode               = "Single"
  tags                        = local.common_tags
  
  template {
    min_replicas = var.container_apps_min_replicas
    max_replicas = var.container_apps_max_replicas
    
    container {
      name   = "order-service"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = var.container_apps_cpu
      memory = var.container_apps_memory
      
      env {
        name  = "SERVICE_BUS_CONNECTION"
        value = azurerm_servicebus_namespace.main.default_primary_connection_string
      }
      
      env {
        name  = "APPINSIGHTS_CONNECTION"
        value = azurerm_application_insights.main.connection_string
      }
      
      env {
        name  = "SERVICE_NAME"
        value = "order-service"
      }
      
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.main.connection_string
      }
    }
  }
  
  ingress {
    external_enabled = true
    target_port      = 80
    
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# Create Inventory Service Container App  
resource "azurerm_container_app" "inventory_service" {
  name                         = "inventory-service"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name         = azurerm_resource_group.main.name
  revision_mode               = "Single"
  tags                        = local.common_tags
  
  template {
    min_replicas = var.container_apps_min_replicas
    max_replicas = 5 # Smaller scale for inventory service
    
    container {
      name   = "inventory-service"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = var.container_apps_cpu
      memory = var.container_apps_memory
      
      env {
        name  = "SERVICE_BUS_CONNECTION"
        value = azurerm_servicebus_namespace.main.default_primary_connection_string
      }
      
      env {
        name  = "APPINSIGHTS_CONNECTION"
        value = azurerm_application_insights.main.connection_string
      }
      
      env {
        name  = "SERVICE_NAME"
        value = "inventory-service"
      }
      
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.main.connection_string
      }
    }
  }
  
  ingress {
    external_enabled = false # Internal only for inventory service
    target_port      = 80
    
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# Create Storage Account for Function Apps
resource "azurerm_storage_account" "function_storage" {
  name                     = local.function_storage_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  
  # Security configuration
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true
  
  tags = local.common_tags
}

# Create Service Plan for Function Apps
resource "azurerm_service_plan" "function_plan" {
  name                = "asp-functions-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  os_type            = "Linux"
  sku_name           = "Y1" # Consumption plan
  tags               = local.common_tags
}

# Create Payment Service Function App
resource "azurerm_linux_function_app" "payment_service" {
  name                = local.payment_function_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  service_plan_id    = azurerm_service_plan.function_plan.id
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  functions_extension_version = var.function_app_version
  tags = local.common_tags
  
  site_config {
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    
    application_stack {
      node_version = var.function_app_runtime == "node" ? "18" : null
    }
  }
  
  app_settings = {
    "SERVICE_BUS_CONNECTION"                = azurerm_servicebus_namespace.main.default_primary_connection_string
    "APPINSIGHTS_CONNECTION"               = azurerm_application_insights.main.connection_string
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "FUNCTIONS_WORKER_RUNTIME"             = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"         = "~18"
    "AzureWebJobsFeatureFlags"            = "EnableWorkerIndexing"
  }
}

# Create Shipping Service Function App
resource "azurerm_linux_function_app" "shipping_service" {
  name                = local.shipping_function_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  service_plan_id    = azurerm_service_plan.function_plan.id
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  functions_extension_version = var.function_app_version
  tags = local.common_tags
  
  site_config {
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    
    application_stack {
      node_version = var.function_app_runtime == "node" ? "18" : null
    }
  }
  
  app_settings = {
    "SERVICE_BUS_CONNECTION"                = azurerm_servicebus_namespace.main.default_primary_connection_string
    "APPINSIGHTS_CONNECTION"               = azurerm_application_insights.main.connection_string
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "FUNCTIONS_WORKER_RUNTIME"             = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION"         = "~18"
    "AzureWebJobsFeatureFlags"            = "EnableWorkerIndexing"
  }
}

# Create Azure Monitor Workbook for Distributed Tracing
resource "azapi_resource" "choreography_workbook" {
  type      = "Microsoft.Insights/workbooks@2022-04-01"
  name      = "choreography-dashboard-${local.resource_suffix}"
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id
  
  body = jsonencode({
    kind = "user"
    properties = {
      displayName = "Microservices Choreography Dashboard"
      category    = "microservices"
      sourceId    = azurerm_log_analytics_workspace.main.id
      serializedData = jsonencode({
        version = "Notebook/1.0"
        items = [
          {
            type = 1
            content = {
              json = "# Microservices Choreography Dashboard\n\nThis workbook provides comprehensive observability for event-driven microservices choreography patterns using Azure Service Bus Premium and distributed tracing."
            }
            name = "title"
          },
          {
            type = 3
            content = {
              version = "KqlItem/1.0"
              query   = "requests\n| where cloud_RoleName in ('order-service', 'inventory-service', 'payment-service', 'shipping-service')\n| summarize RequestCount = count() by bin(timestamp, 5m), cloud_RoleName\n| render timechart"
              size    = 0
              title   = "Request Volume by Service"
              timeContext = {
                durationMs = 3600000
              }
              queryType = 0
              resourceType = "microsoft.insights/components"
              visualization = "timechart"
            }
            name = "requestVolume"
          },
          {
            type = 3
            content = {
              version = "KqlItem/1.0"
              query   = "dependencies\n| where type == 'Azure Service Bus'\n| summarize MessageCount = count() by bin(timestamp, 5m), cloud_RoleName\n| render timechart"
              size    = 0
              title   = "Service Bus Messages by Service"
              timeContext = {
                durationMs = 3600000
              }
              queryType = 0
              resourceType = "microsoft.insights/components"
              visualization = "timechart"
            }
            name = "serviceBusMessages"
          },
          {
            type = 3
            content = {
              version = "KqlItem/1.0"
              query   = "requests\n| where cloud_RoleName in ('order-service', 'inventory-service', 'payment-service', 'shipping-service')\n| summarize AvgDuration = avg(duration) by cloud_RoleName\n| render barchart"
              size    = 0
              title   = "Average Response Time by Service"
              timeContext = {
                durationMs = 3600000
              }
              queryType = 0
              resourceType = "microsoft.insights/components"
              visualization = "barchart"
            }
            name = "responseTime"
          },
          {
            type = 3
            content = {
              version = "KqlItem/1.0"
              query   = "exceptions\n| where cloud_RoleName in ('order-service', 'inventory-service', 'payment-service', 'shipping-service')\n| summarize ExceptionCount = count() by bin(timestamp, 15m), cloud_RoleName\n| render timechart"
              size    = 0
              title   = "Exception Rate by Service"
              timeContext = {
                durationMs = 3600000
              }
              queryType = 0
              resourceType = "microsoft.insights/components"
              visualization = "timechart"
            }
            name = "exceptions"
          },
          {
            type = 3
            content = {
              version = "KqlItem/1.0"
              query   = "traces\n| where cloud_RoleName in ('order-service', 'inventory-service', 'payment-service', 'shipping-service')\n| where severityLevel >= 2\n| summarize LogCount = count() by bin(timestamp, 10m), severityLevel, cloud_RoleName\n| render timechart"
              size    = 0
              title   = "Log Volume by Severity and Service"
              timeContext = {
                durationMs = 3600000
              }
              queryType = 0
              resourceType = "microsoft.insights/components"
              visualization = "timechart"
            }
            name = "logVolume"
          }
        ]
      })
    }
  })
  
  tags = local.common_tags
}

# Create Diagnostic Settings for Service Bus (if enabled)
resource "azurerm_monitor_diagnostic_setting" "service_bus" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "diag-${azurerm_servicebus_namespace.main.name}"
  target_resource_id = azurerm_servicebus_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable logs
  enabled_log {
    category = "OperationalLogs"
  }
  
  enabled_log {
    category = "VNetAndIPFilteringLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create Diagnostic Settings for Container Apps Environment (if enabled)
resource "azurerm_monitor_diagnostic_setting" "container_environment" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "diag-${azurerm_container_app_environment.main.name}"
  target_resource_id = azurerm_container_app_environment.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable logs
  enabled_log {
    category = "ContainerAppConsoleLogs"
  }
  
  enabled_log {
    category = "ContainerAppSystemLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create Diagnostic Settings for Function Apps (if enabled)
resource "azurerm_monitor_diagnostic_setting" "payment_function" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "diag-${azurerm_linux_function_app.payment_service.name}"
  target_resource_id = azurerm_linux_function_app.payment_service.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable logs
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "shipping_function" {
  count              = var.enable_diagnostic_settings ? 1 : 0
  name               = "diag-${azurerm_linux_function_app.shipping_service.name}"
  target_resource_id = azurerm_linux_function_app.shipping_service.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Enable logs
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}