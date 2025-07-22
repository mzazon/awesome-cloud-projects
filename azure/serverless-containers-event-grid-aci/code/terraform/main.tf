# Random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  
  tags = var.tags
}

# Storage Account for blob events and container templates
resource "azurerm_storage_account" "main" {
  name                     = "${var.storage_account_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Security configurations
  https_traffic_only_enabled = var.enable_https_traffic_only
  min_tls_version            = "TLS1_2"
  
  # Enable hierarchical namespace is disabled for Event Grid compatibility
  is_hns_enabled = false
  
  # Enable blob versioning and change feed for advanced scenarios
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Enable container delete retention
    container_delete_retention_policy {
      days = 7
    }
    
    # Enable blob delete retention
    delete_retention_policy {
      days = 7
    }
  }
  
  # Network access rules for enhanced security
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  tags = var.tags
}

# Storage containers for input and output data
resource "azurerm_storage_container" "input" {
  name                  = "input"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_storage_container" "output" {
  name                  = "output"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Container Registry for custom container images
resource "azurerm_container_registry" "main" {
  name                = "${var.container_registry_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = true
  
  # Enable geo-replication for premium SKU
  dynamic "georeplications" {
    for_each = var.container_registry_sku == "Premium" ? [1] : []
    content {
      location = "West US 2"
      tags     = var.tags
    }
  }
  
  # Network access rules for enhanced security
  network_rule_set {
    default_action = "Allow"
  }
  
  tags = var.tags
}

# Event Grid Topic for container orchestration
resource "azurerm_eventgrid_topic" "main" {
  name                = var.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Input schema configuration
  input_schema = "EventGridSchema"
  
  # Public network access configuration
  public_network_access_enabled = true
  
  tags = var.tags
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.log_analytics_workspace_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = 30
  
  # Enable daily cap for cost control
  daily_quota_gb = 1
  
  tags = var.tags
}

# Application Insights for function app monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-event-processor-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  # Retention configuration
  retention_in_days = 30
  
  tags = var.tags
}

# Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = "sp-event-processor-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption plan
  
  tags = var.tags
}

# Function App for Event Grid webhook processing
resource "azurerm_linux_function_app" "main" {
  name                = "${var.function_app_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  # Storage account for function app
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Site configuration
  site_config {
    application_stack {
      node_version = "18"
    }
    
    # Enable Always On for better performance (not available in consumption plan)
    always_on = false
    
    # CORS configuration for Event Grid
    cors {
      allowed_origins = ["*"]
      support_credentials = false
    }
  }
  
  # Application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "CONTAINER_REGISTRY_NAME"      = azurerm_container_registry.main.name
    "CONTAINER_REGISTRY_SERVER"    = azurerm_container_registry.main.login_server
    "CONTAINER_REGISTRY_USERNAME"  = azurerm_container_registry.main.admin_username
    "CONTAINER_REGISTRY_PASSWORD"  = azurerm_container_registry.main.admin_password
    "STORAGE_ACCOUNT_NAME"         = azurerm_storage_account.main.name
    "STORAGE_ACCOUNT_KEY"          = azurerm_storage_account.main.primary_access_key
    "RESOURCE_GROUP_NAME"          = azurerm_resource_group.main.name
    "SUBSCRIPTION_ID"              = data.azurerm_client_config.current.subscription_id
    "EVENT_GRID_TOPIC_ENDPOINT"    = azurerm_eventgrid_topic.main.endpoint
    "EVENT_GRID_TOPIC_KEY"         = azurerm_eventgrid_topic.main.primary_access_key
    "LOG_ANALYTICS_WORKSPACE_ID"   = azurerm_log_analytics_workspace.main.workspace_id
    "LOG_ANALYTICS_WORKSPACE_KEY"  = azurerm_log_analytics_workspace.main.primary_shared_key
  }
  
  # Function app identity for accessing other Azure resources
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
}

# Role assignment for Function App to create Container Instances
resource "azurerm_role_assignment" "function_app_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Sample Container Instance for event processing
resource "azurerm_container_group" "event_processor" {
  name                = "event-processor-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_address_type     = "Public"
  dns_name_label      = "event-processor-${random_string.suffix.result}"
  os_type             = "Linux"
  restart_policy      = var.container_restart_policy
  
  # Container configuration
  container {
    name   = "event-processor"
    image  = "mcr.microsoft.com/azure-functions/dotnet:3.0"
    cpu    = var.container_cpu
    memory = var.container_memory
    
    # Port configuration for webhook endpoint
    ports {
      port     = 80
      protocol = "TCP"
    }
    
    # Environment variables for container
    environment_variables = {
      "STORAGE_ACCOUNT_NAME" = azurerm_storage_account.main.name
      "EVENT_GRID_TOPIC"     = azurerm_eventgrid_topic.main.name
    }
    
    # Secure environment variables
    secure_environment_variables = {
      "STORAGE_ACCOUNT_KEY" = azurerm_storage_account.main.primary_access_key
      "EVENT_GRID_TOPIC_KEY" = azurerm_eventgrid_topic.main.primary_access_key
    }
  }
  
  # Enable container insights if specified
  dynamic "diagnostics" {
    for_each = var.enable_container_insights ? [1] : []
    content {
      log_analytics {
        workspace_id  = azurerm_log_analytics_workspace.main.workspace_id
        workspace_key = azurerm_log_analytics_workspace.main.primary_shared_key
      }
    }
  }
  
  tags = var.tags
}

# Sample image processing Container Instance
resource "azurerm_container_group" "image_processor" {
  name                = "image-processor-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_address_type     = "None"
  os_type             = "Linux"
  restart_policy      = var.container_restart_policy
  
  # Container configuration
  container {
    name   = "image-processor"
    image  = "mcr.microsoft.com/azure-cli:latest"
    cpu    = var.container_cpu
    memory = var.container_memory
    
    # Environment variables for container
    environment_variables = {
      "STORAGE_ACCOUNT_NAME" = azurerm_storage_account.main.name
    }
    
    # Secure environment variables
    secure_environment_variables = {
      "STORAGE_ACCOUNT_KEY" = azurerm_storage_account.main.primary_access_key
    }
    
    # Command to keep container running for demonstration
    commands = ["sleep", "3600"]
  }
  
  # Enable container insights if specified
  dynamic "diagnostics" {
    for_each = var.enable_container_insights ? [1] : []
    content {
      log_analytics {
        workspace_id  = azurerm_log_analytics_workspace.main.workspace_id
        workspace_key = azurerm_log_analytics_workspace.main.primary_shared_key
      }
    }
  }
  
  tags = var.tags
}

# Event Grid Event Subscription for blob events to function app
resource "azurerm_eventgrid_event_subscription" "blob_events" {
  name                 = "blob-events-subscription"
  scope                = azurerm_storage_account.main.id
  webhook_endpoint {
    url = "https://${azurerm_linux_function_app.main.default_hostname}/api/ProcessStorageEvent"
  }
  
  # Event types to subscribe to
  included_event_types = ["Microsoft.Storage.BlobCreated"]
  
  # Subject filtering for specific containers
  subject_filter {
    subject_begins_with = "/blobServices/default/containers/input/"
  }
  
  # Advanced filtering for image files
  advanced_filter {
    string_contains {
      key = "data.contentType"
      values = ["image"]
    }
  }
  
  # Retry policy configuration
  retry_policy {
    max_delivery_attempts = var.event_grid_max_delivery_attempts
    event_time_to_live    = var.event_grid_event_retention_time
  }
  
  # Dead letter configuration
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = "deadletter"
  }
  
  depends_on = [azurerm_storage_container.input, azurerm_linux_function_app.main]
}

# Dead letter container for failed events
resource "azurerm_storage_container" "deadletter" {
  name                  = "deadletter"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Action Group for alerting
resource "azurerm_monitor_action_group" "container_alerts" {
  name                = "container-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ContainerAlerts"
  
  tags = var.tags
}

# Container template stored in blob storage
resource "azurerm_storage_blob" "container_template" {
  name                   = "container-template.json"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.output.name
  type                   = "Block"
  
  # Container template JSON content
  source_content = jsonencode({
    name     = "dynamic-processor-{unique_id}"
    location = var.location
    properties = {
      containers = [
        {
          name = "event-processor"
          properties = {
            image = "mcr.microsoft.com/azure-cli:latest"
            resources = {
              requests = {
                cpu        = var.container_cpu
                memoryInGB = var.container_memory
              }
            }
            environmentVariables = [
              {
                name  = "STORAGE_ACCOUNT"
                value = "{storage_account}"
              },
              {
                name  = "BLOB_URL"
                value = "{blob_url}"
              },
              {
                name  = "EVENT_TYPE"
                value = "{event_type}"
              }
            ]
            command = [
              "/bin/sh",
              "-c",
              "echo 'Processing event for blob: ${BLOB_URL}' && sleep 30 && echo 'Processing complete'"
            ]
          }
        }
      ]
      restartPolicy = "Never"
      osType        = "Linux"
    }
  })
  
  depends_on = [azurerm_storage_container.output]
}

# Metric alerts for container monitoring
resource "azurerm_monitor_metric_alert" "container_cpu_usage" {
  name                = "container-cpu-usage-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_group.event_processor.id]
  description         = "Alert when container CPU usage is high"
  
  # Alert criteria
  criteria {
    metric_namespace = "Microsoft.ContainerInstance/containerGroups"
    metric_name      = "CpuUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  # Action to take when alert is triggered
  action {
    action_group_id = azurerm_monitor_action_group.container_alerts.id
  }
  
  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "container_memory_usage" {
  name                = "container-memory-usage-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_group.event_processor.id]
  description         = "Alert when container memory usage is high"
  
  # Alert criteria
  criteria {
    metric_namespace = "Microsoft.ContainerInstance/containerGroups"
    metric_name      = "MemoryUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  # Action to take when alert is triggered
  action {
    action_group_id = azurerm_monitor_action_group.container_alerts.id
  }
  
  tags = var.tags
}