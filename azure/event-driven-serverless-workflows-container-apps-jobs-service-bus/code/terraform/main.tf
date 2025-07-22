# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Get current client configuration for tenant and subscription info
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create Log Analytics Workspace for Container Apps Environment
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-analytics-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# Create Azure Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                       = var.container_apps_environment_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = var.tags
}

# Create Service Bus Namespace
resource "azurerm_servicebus_namespace" "main" {
  name                = var.service_bus_namespace_name != "" ? var.service_bus_namespace_name : "sb-container-jobs-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.service_bus_sku
  tags                = var.tags
}

# Create Service Bus Queue
resource "azurerm_servicebus_queue" "main" {
  name         = var.queue_name
  namespace_id = azurerm_servicebus_namespace.main.id

  # Message handling configuration
  max_delivery_count        = var.queue_max_delivery_count
  lock_duration            = var.queue_lock_duration
  default_message_ttl      = "P14D"  # 14 days
  duplicate_detection_history_time_window = "PT10M"  # 10 minutes

  # Enable dead lettering
  dead_lettering_on_message_expiration = true
  
  # Enable duplicate detection for Standard/Premium tiers
  requires_duplicate_detection = var.service_bus_sku != "Basic"
  
  # Enable sessions for advanced scenarios (optional)
  requires_session = false
}

# Get Service Bus authorization rule for connection string
data "azurerm_servicebus_namespace_authorization_rule" "main" {
  name         = "RootManageSharedAccessKey"
  namespace_id = azurerm_servicebus_namespace.main.id
}

# Create Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = var.container_registry_name != "" ? var.container_registry_name : "acrjobs${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.container_registry_admin_enabled
  
  # Enable geo-replication for Premium SKU
  dynamic "georeplications" {
    for_each = var.container_registry_sku == "Premium" ? [1] : []
    content {
      location                = var.location == "East US" ? "West US 2" : "East US"
      zone_redundancy_enabled = false
      tags                    = var.tags
    }
  }
  
  # Enable network rule set for Premium SKU
  dynamic "network_rule_set" {
    for_each = var.container_registry_sku == "Premium" ? [1] : []
    content {
      default_action = "Allow"
    }
  }
  
  tags = var.tags
}

# Create Container Apps Job
resource "azurerm_container_app_job" "main" {
  name                         = var.container_apps_job_name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  container_app_environment_id = azurerm_container_app_environment.main.id
  
  replica_timeout_in_seconds = var.job_replica_timeout
  replica_retry_limit        = var.job_replica_retry_limit
  
  # Manual trigger configuration (default)
  manual_trigger_config {
    replica_completion_count = var.job_replica_completion_count
    parallelism              = var.job_parallelism
  }
  
  # Event-driven trigger configuration for Service Bus
  event_trigger_config {
    replica_completion_count = var.job_replica_completion_count
    parallelism              = var.job_parallelism
    
    scale {
      min_executions = var.job_min_executions
      max_executions = var.job_max_executions
      
      rules {
        name = "servicebus-queue-rule"
        type = "azure-servicebus"
        
        metadata = {
          queueName    = var.queue_name
          namespace    = azurerm_servicebus_namespace.main.name
          messageCount = tostring(var.job_scale_rule_message_count)
        }
        
        authentication {
          secret_name       = "servicebus-connection-secret"
          trigger_parameter = "connection"
        }
      }
    }
  }
  
  # Template configuration
  template {
    container {
      name   = "message-processor"
      image  = "${azurerm_container_registry.main.login_server}/${var.container_image_name}"
      cpu    = tonumber(var.container_cpu)
      memory = var.container_memory
      
      # Environment variables
      env {
        name        = "SERVICE_BUS_CONNECTION_STRING"
        secret_name = "servicebus-connection-secret"
      }
      
      env {
        name  = "QUEUE_NAME"
        value = var.queue_name
      }
      
      env {
        name  = "AZURE_CLIENT_ID"
        value = ""  # Will be set if using managed identity
      }
    }
  }
  
  # Registry configuration
  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "registry-password-secret"
  }
  
  # Secrets configuration
  secret {
    name  = "servicebus-connection-secret"
    value = data.azurerm_servicebus_namespace_authorization_rule.main.primary_connection_string
  }
  
  secret {
    name  = "registry-password-secret"
    value = azurerm_container_registry.main.admin_password
  }
  
  tags = var.tags
  
  depends_on = [
    azurerm_servicebus_queue.main,
    azurerm_container_registry.main
  ]
}

# Create Action Group for alerts (if monitoring is enabled)
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "ag-container-job-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "jobAlerts"
  
  email_receiver {
    name          = "admin-email"
    email_address = "admin@example.com"  # Change this to your email
  }
  
  tags = var.tags
}

# Create metric alert for job failures (if monitoring is enabled)
resource "azurerm_monitor_metric_alert" "job_failure" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "container-job-failure-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app_job.main.id]
  description         = "Alert when container job executions fail"
  severity            = var.alert_severity
  frequency           = var.alert_evaluation_frequency
  window_size         = var.alert_window_size
  
  criteria {
    metric_namespace = "Microsoft.App/jobs"
    metric_name      = "JobExecutionCount"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 0
    
    dimension {
      name     = "Result"
      operator = "Include"
      values   = ["Failed"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = var.tags
}

# Create metric alert for queue depth monitoring (if monitoring is enabled)
resource "azurerm_monitor_metric_alert" "queue_depth" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "servicebus-queue-depth-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_servicebus_namespace.main.id]
  description         = "Alert when Service Bus queue has high message count"
  severity            = var.alert_severity
  frequency           = var.alert_evaluation_frequency
  window_size         = var.alert_window_size
  
  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "ActiveMessages"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 100  # Alert when queue has more than 100 messages
    
    dimension {
      name     = "EntityName"
      operator = "Include"
      values   = [var.queue_name]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = var.tags
}

# Optional: Create managed identity for the Container Apps Job
resource "azurerm_user_assigned_identity" "job_identity" {
  name                = "mi-${var.container_apps_job_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Grant the managed identity access to Service Bus
resource "azurerm_role_assignment" "servicebus_data_receiver" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.job_identity.principal_id
}

resource "azurerm_role_assignment" "servicebus_data_sender" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.job_identity.principal_id
}

# Grant the managed identity access to Container Registry
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.job_identity.principal_id
}