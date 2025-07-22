# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags     = var.tags
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = merge(var.tags, {
    Component = "Monitoring"
  })
}

# Create Application Insights for OpenAI monitoring
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "appi-${var.project_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  tags = merge(var.tags, {
    Component = "Monitoring"
  })
}

# Create Azure OpenAI Service
resource "azurerm_cognitive_account" "openai" {
  name                  = "openai-${var.project_name}-${random_id.suffix.hex}"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  kind                  = "OpenAI"
  sku_name              = var.openai_sku
  custom_domain         = "openai-${var.project_name}-${random_id.suffix.hex}"
  public_network_access = length(var.allowed_ip_ranges) > 0 ? "Disabled" : "Enabled"
  
  # Configure network access if IP ranges are specified
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
    }
  }
  
  tags = merge(var.tags, {
    Component = "AI Processing"
  })
}

# Deploy GPT-4 model for Assistants API
resource "azurerm_cognitive_deployment" "gpt4" {
  name                 = var.gpt4_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = "gpt-4"
    version = var.gpt4_model_version
  }
  
  scale {
    type = var.gpt4_scale_type
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# Create Service Bus Namespace for message orchestration
resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${var.project_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.servicebus_sku
  
  # Enable zone redundancy for production workloads
  zone_redundant = var.environment == "prod" ? true : false
  
  tags = merge(var.tags, {
    Component = "Messaging"
  })
}

# Create Service Bus Queue for processing tasks
resource "azurerm_servicebus_queue" "processing" {
  name         = "processing-queue"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Configure queue properties
  max_size_in_megabytes                = var.processing_queue_max_size
  default_message_ttl                  = "PT${var.message_ttl_minutes}M"
  max_delivery_count                   = 10
  dead_lettering_on_message_expiration = true
  
  # Enable duplicate detection
  requires_duplicate_detection = true
  duplicate_detection_history_time_window = "PT10M"
  
  # Enable sessions for ordered processing
  requires_session = false
}

# Create Service Bus Topic for broadcasting results
resource "azurerm_servicebus_topic" "results" {
  name         = "processing-results"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Configure topic properties
  max_size_in_megabytes = var.processing_queue_max_size
  default_message_ttl   = "PT${var.message_ttl_minutes}M"
  
  # Enable duplicate detection
  requires_duplicate_detection = true
  duplicate_detection_history_time_window = "PT10M"
}

# Create Service Bus Topic Subscription for notifications
resource "azurerm_servicebus_subscription" "notifications" {
  name     = "notification-sub"
  topic_id = azurerm_servicebus_topic.results.id
  
  max_delivery_count                   = 10
  default_message_ttl                  = "PT${var.message_ttl_minutes}M"
  dead_lettering_on_message_expiration = true
  dead_lettering_on_filter_evaluation_error = true
}

# Create Container Registry for job images
resource "azurerm_container_registry" "main" {
  name                = "acr${replace(var.project_name, "-", "")}${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = true
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Configure network access
  public_network_access_enabled = length(var.allowed_ip_ranges) == 0 ? true : false
  
  dynamic "network_rule_set" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      
      dynamic "ip_rule" {
        for_each = var.allowed_ip_ranges
        content {
          action   = "Allow"
          ip_range = ip_rule.value
        }
      }
    }
  }
  
  tags = merge(var.tags, {
    Component = "Container Registry"
  })
}

# Create Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                       = "aca-env-${var.project_name}-${random_id.suffix.hex}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  tags = merge(var.tags, {
    Component = "Container Platform"
  })
}

# Create managed identity for Container Apps
resource "azurerm_user_assigned_identity" "container_apps" {
  count = var.enable_system_assigned_identity ? 1 : 0
  
  name                = "id-${var.project_name}-container-apps-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  tags = merge(var.tags, {
    Component = "Identity"
  })
}

# Grant Container Apps identity access to Container Registry
resource "azurerm_role_assignment" "container_apps_acr_pull" {
  count = var.enable_system_assigned_identity ? 1 : 0
  
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.container_apps[0].principal_id
}

# Grant Container Apps identity access to Service Bus
resource "azurerm_role_assignment" "container_apps_servicebus_sender" {
  count = var.enable_system_assigned_identity ? 1 : 0
  
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.container_apps[0].principal_id
}

resource "azurerm_role_assignment" "container_apps_servicebus_receiver" {
  count = var.enable_system_assigned_identity ? 1 : 0
  
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.container_apps[0].principal_id
}

# Create Document Processing Container App Job
resource "azurerm_container_app_job" "document_processor" {
  name                         = "document-processor"
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  
  replica_timeout_in_seconds = var.job_replica_timeout
  replica_retry_limit        = var.job_retry_limit
  manual_trigger_config {
    parallelism              = var.job_parallelism
    replica_completion_count = 1
  }
  
  # Configure event-driven scaling with KEDA
  event_trigger_config {
    parallelism              = var.job_parallelism
    replica_completion_count = 1
    
    scale {
      min_replicas = 0
      max_replicas = 10
      
      rules {
        name             = "servicebus-scale"
        custom_rule_type = "azure-servicebus"
        metadata = {
          connectionFromEnv = "SERVICEBUS_CONNECTION"
          queueName         = azurerm_servicebus_queue.processing.name
          messageCount      = "1"
        }
      }
    }
  }
  
  template {
    container {
      name   = "document-processor"
      image  = "${azurerm_container_registry.main.login_server}/processing-job:latest"
      cpu    = 0.5
      memory = "1Gi"
      
      env {
        name        = "SERVICEBUS_CONNECTION"
        secret_name = "servicebus-connection"
      }
      
      env {
        name  = "OPENAI_ENDPOINT"
        value = azurerm_cognitive_account.openai.endpoint
      }
      
      env {
        name        = "OPENAI_API_KEY"
        secret_name = "openai-api-key"
      }
      
      env {
        name  = "PROCESSING_QUEUE_NAME"
        value = azurerm_servicebus_queue.processing.name
      }
      
      env {
        name  = "RESULTS_TOPIC_NAME"
        value = azurerm_servicebus_topic.results.name
      }
    }
  }
  
  # Configure registry authentication
  dynamic "registry" {
    for_each = var.enable_system_assigned_identity ? [1] : []
    content {
      server   = azurerm_container_registry.main.login_server
      identity = azurerm_user_assigned_identity.container_apps[0].id
    }
  }
  
  # Configure managed identity
  dynamic "identity" {
    for_each = var.enable_system_assigned_identity ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.container_apps[0].id]
    }
  }
  
  secret {
    name  = "servicebus-connection"
    value = azurerm_servicebus_namespace.main.default_primary_connection_string
  }
  
  secret {
    name  = "openai-api-key"
    value = azurerm_cognitive_account.openai.primary_access_key
  }
  
  tags = merge(var.tags, {
    Component = "Processing Jobs"
    JobType   = "Document Processor"
  })
  
  depends_on = [
    azurerm_role_assignment.container_apps_acr_pull,
    azurerm_role_assignment.container_apps_servicebus_sender,
    azurerm_role_assignment.container_apps_servicebus_receiver
  ]
}

# Create Notification Service Container App Job
resource "azurerm_container_app_job" "notification_service" {
  name                         = "notification-service"
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  
  replica_timeout_in_seconds = 120
  replica_retry_limit        = var.job_retry_limit
  manual_trigger_config {
    parallelism              = 2
    replica_completion_count = 1
  }
  
  # Configure event-driven scaling for topic subscription
  event_trigger_config {
    parallelism              = 2
    replica_completion_count = 1
    
    scale {
      min_replicas = 0
      max_replicas = 5
      
      rules {
        name             = "servicebus-topic-scale"
        custom_rule_type = "azure-servicebus"
        metadata = {
          connectionFromEnv  = "SERVICEBUS_CONNECTION"
          topicName          = azurerm_servicebus_topic.results.name
          subscriptionName   = azurerm_servicebus_subscription.notifications.name
          messageCount       = "1"
        }
      }
    }
  }
  
  template {
    container {
      name   = "notification-service"
      image  = "${azurerm_container_registry.main.login_server}/notification-job:latest"
      cpu    = 0.25
      memory = "0.5Gi"
      
      env {
        name        = "SERVICEBUS_CONNECTION"
        secret_name = "servicebus-connection"
      }
      
      env {
        name  = "RESULTS_TOPIC_NAME"
        value = azurerm_servicebus_topic.results.name
      }
      
      env {
        name  = "NOTIFICATION_SUBSCRIPTION_NAME"
        value = azurerm_servicebus_subscription.notifications.name
      }
    }
  }
  
  # Configure registry authentication
  dynamic "registry" {
    for_each = var.enable_system_assigned_identity ? [1] : []
    content {
      server   = azurerm_container_registry.main.login_server
      identity = azurerm_user_assigned_identity.container_apps[0].id
    }
  }
  
  # Configure managed identity
  dynamic "identity" {
    for_each = var.enable_system_assigned_identity ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.container_apps[0].id]
    }
  }
  
  secret {
    name  = "servicebus-connection"
    value = azurerm_servicebus_namespace.main.default_primary_connection_string
  }
  
  tags = merge(var.tags, {
    Component = "Processing Jobs"
    JobType   = "Notification Service"
  })
  
  depends_on = [
    azurerm_role_assignment.container_apps_acr_pull,
    azurerm_role_assignment.container_apps_servicebus_sender,
    azurerm_role_assignment.container_apps_servicebus_receiver
  ]
}

# Create monitoring alerts for system health
resource "azurerm_monitor_metric_alert" "openai_high_usage" {
  count = var.enable_advanced_monitoring ? 1 : 0
  
  name                = "OpenAI High API Usage"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cognitive_account.openai.id]
  description         = "Alert when OpenAI API usage is high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "ProcessedTokens"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 10000
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = merge(var.tags, {
    Component = "Monitoring"
  })
}

# Create action group for alerts
resource "azurerm_monitor_action_group" "main" {
  count = var.enable_advanced_monitoring ? 1 : 0
  
  name                = "ag-${var.project_name}-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "IntelliAuto"
  
  tags = merge(var.tags, {
    Component = "Monitoring"
  })
}

# Create dashboard for monitoring
resource "azurerm_portal_dashboard" "main" {
  count = var.enable_dashboard ? 1 : 0
  
  name                = "dashboard-${var.project_name}-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          "0" = {
            position = {
              x        = 0
              y        = 0
              rowSpan  = 4
              colSpan  = 6
            }
            metadata = {
              inputs = []
              type   = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = azurerm_cognitive_account.openai.id
                          }
                          name = "ProcessedTokens"
                          aggregationType = {
                            type = "Average"
                          }
                        }
                      ]
                      title = "OpenAI API Usage"
                      titleKind = 1
                      visualization = {
                        chartType = 2
                      }
                    }
                  }
                }
              }
            }
          }
          "1" = {
            position = {
              x        = 6
              y        = 0
              rowSpan  = 4
              colSpan  = 6
            }
            metadata = {
              inputs = []
              type   = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = azurerm_servicebus_namespace.main.id
                          }
                          name = "Messages"
                          aggregationType = {
                            type = "Total"
                          }
                        }
                      ]
                      title = "Service Bus Message Count"
                      titleKind = 1
                      visualization = {
                        chartType = 2
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
  })
  
  tags = merge(var.tags, {
    Component = "Monitoring"
  })
}