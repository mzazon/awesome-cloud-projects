# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  
  tags = merge(var.common_tags, {
    Component = "core-infrastructure"
  })
}

# Create Log Analytics Workspace for Application Insights
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = merge(var.common_tags, {
    Component = "monitoring"
  })
}

# Create Application Insights
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  sampling_percentage = var.application_insights_sampling_percentage

  tags = merge(var.common_tags, {
    Component = "monitoring"
  })
}

# Create Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "acr${var.project_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.container_registry_admin_enabled

  # Enable content trust for Premium SKU
  dynamic "trust_policy" {
    for_each = var.container_registry_sku == "Premium" ? [1] : []
    content {
      enabled = true
    }
  }

  # Enable retention policy for Premium SKU
  dynamic "retention_policy" {
    for_each = var.container_registry_sku == "Premium" ? [1] : []
    content {
      days    = 7
      enabled = true
    }
  }

  tags = merge(var.common_tags, {
    Component = "container-registry"
  })
}

# Create Storage Account for call recordings
resource "azurerm_storage_account" "recordings" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  access_tier              = var.storage_account_access_tier
  
  # Enable blob versioning and soft delete
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  # Enable network rules for enhanced security
  network_rules {
    default_action             = "Allow"
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = []
  }

  tags = merge(var.common_tags, {
    Component = "storage"
  })
}

# Create storage container for call recordings
resource "azurerm_storage_container" "recordings" {
  name                  = "recordings"
  storage_account_name  = azurerm_storage_account.recordings.name
  container_access_type = "private"
}

# Create Azure Communication Services
resource "azurerm_communication_service" "main" {
  name                = "cs-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  data_location       = var.communication_services_data_location

  tags = merge(var.common_tags, {
    Component = "communication-services"
  })
}

# Create App Service Plan for Web App
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  os_type  = "Linux"
  sku_name = var.app_service_plan_sku

  # Set worker count
  worker_count = var.app_service_plan_worker_count

  tags = merge(var.common_tags, {
    Component = "compute"
  })
}

# Create Web App for Containers
resource "azurerm_linux_web_app" "main" {
  name                = "webapp-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id

  # Enable HTTPS only
  https_only = var.web_app_https_only

  # Configure site settings
  site_config {
    always_on                         = var.web_app_always_on
    ftps_state                       = var.web_app_ftps_state
    container_registry_use_managed_identity = false
    
    # Configure container settings
    application_stack {
      docker_image_name   = "${azurerm_container_registry.acr.login_server}/${var.container_image_name}:${var.container_image_tag}"
      docker_registry_url = "https://${azurerm_container_registry.acr.login_server}"
      docker_registry_username = azurerm_container_registry.acr.admin_username
      docker_registry_password = azurerm_container_registry.acr.admin_password
    }

    # Configure IP restrictions if specified
    dynamic "ip_restriction" {
      for_each = var.allowed_ip_ranges
      content {
        ip_address = ip_restriction.value
        action     = "Allow"
      }
    }
  }

  # Configure application settings
  app_settings = {
    "ACS_CONNECTION_STRING"                = azurerm_communication_service.main.primary_connection_string
    "STORAGE_CONNECTION_STRING"           = azurerm_storage_account.recordings.primary_connection_string
    "APPINSIGHTS_INSTRUMENTATION_KEY"     = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "NODE_ENV"                            = var.node_env
    "PORT"                                = var.container_port
    "WEBSITES_PORT"                       = var.container_port
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "DOCKER_ENABLE_CI"                    = "true"
  }

  # Configure logging
  logs {
    detailed_error_messages = true
    failed_request_tracing  = true
    
    http_logs {
      file_system {
        retention_in_days = var.log_retention_days
        retention_in_mb   = 35
      }
    }
  }

  # Configure identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.common_tags, {
    Component = "web-app"
  })

  depends_on = [
    azurerm_container_registry.acr,
    azurerm_communication_service.main,
    azurerm_storage_account.recordings,
    azurerm_application_insights.main
  ]
}

# Create Auto-scaling settings
resource "azurerm_monitor_autoscale_setting" "main" {
  count               = var.autoscale_enabled ? 1 : 0
  name                = "autoscale-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_service_plan.main.id

  # Default profile for auto-scaling
  profile {
    name = "default"

    # Capacity settings
    capacity {
      default = var.autoscale_default_instances
      minimum = var.autoscale_min_instances
      maximum = var.autoscale_max_instances
    }

    # Scale-out rule based on CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_cpu_threshold_out
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale-in rule based on CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_cpu_threshold_in
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale-out rule based on memory
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale-in rule based on memory
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 40
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  # Weekend profile with different scaling rules
  profile {
    name = "weekend"

    capacity {
      default = 1
      minimum = 1
      maximum = 5
    }

    recurrence {
      timezone = "UTC"
      days     = ["Saturday", "Sunday"]
      hours    = [0]
      minutes  = [0]
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 20
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  tags = merge(var.common_tags, {
    Component = "autoscaling"
  })
}

# Create Action Group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "videoconf"

  tags = merge(var.common_tags, {
    Component = "monitoring"
  })
}

# Create alerts for high CPU usage
resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "alert-high-cpu-${var.project_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_service_plan.main.id]
  description         = "Alert when CPU usage is high"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = merge(var.common_tags, {
    Component = "monitoring"
  })
}

# Create alerts for high memory usage
resource "azurerm_monitor_metric_alert" "high_memory" {
  name                = "alert-high-memory-${var.project_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_service_plan.main.id]
  description         = "Alert when memory usage is high"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = merge(var.common_tags, {
    Component = "monitoring"
  })
}

# Create alerts for web app response time
resource "azurerm_monitor_metric_alert" "response_time" {
  name                = "alert-response-time-${var.project_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Alert when response time is high"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "AverageResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = merge(var.common_tags, {
    Component = "monitoring"
  })
}

# Create storage lifecycle management policy
resource "azurerm_storage_management_policy" "recordings" {
  storage_account_id = azurerm_storage_account.recordings.id

  rule {
    name    = "recording-lifecycle"
    enabled = true

    filters {
      prefix_match = ["recordings/"]
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

# Grant Web App managed identity access to storage
resource "azurerm_role_assignment" "webapp_storage" {
  scope                = azurerm_storage_account.recordings.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Grant Web App managed identity access to Container Registry
resource "azurerm_role_assignment" "webapp_acr" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Create private endpoint for storage account (optional)
resource "azurerm_private_endpoint" "storage" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "pe-storage-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id

  private_service_connection {
    name                           = "psc-storage-${var.project_name}"
    private_connection_resource_id = azurerm_storage_account.recordings.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  tags = merge(var.common_tags, {
    Component = "networking"
  })
}

# Create virtual network for private endpoints (optional)
resource "azurerm_virtual_network" "main" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "vnet-${var.project_name}-${random_string.suffix.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.common_tags, {
    Component = "networking"
  })
}

# Create subnet for private endpoints
resource "azurerm_subnet" "private_endpoints" {
  count                = var.enable_private_endpoint ? 1 : 0
  name                 = "subnet-private-endpoints"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.1.0/24"]

  private_endpoint_network_policies_enabled = false
}