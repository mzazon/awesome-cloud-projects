# Azure Distributed Session Management Infrastructure
# This Terraform configuration deploys a complete distributed session management solution
# using Azure Managed Redis and Azure App Service with monitoring and security best practices

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local variables for consistent naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix = random_string.suffix.result
  
  # Common resource names
  resource_group_name    = "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  redis_name            = "redis-${var.project_name}-${local.resource_suffix}"
  app_service_plan_name = "plan-${var.project_name}-${local.resource_suffix}"
  web_app_name          = "app-${var.project_name}-${local.resource_suffix}"
  vnet_name             = "vnet-${var.project_name}-${local.resource_suffix}"
  subnet_name           = "subnet-redis"
  workspace_name        = "law-${var.project_name}-${local.resource_suffix}"
  app_insights_name     = "ai-${var.project_name}-${local.resource_suffix}"
  
  # Common tags merged with user-provided tags
  common_tags = merge(var.tags, {
    Project           = var.project_name
    Environment       = var.environment
    TerraformManaged  = "true"
    CreatedDate       = timestamp()
  })
  
  # Redis connection string format
  redis_connection_string = "${azurerm_redis_cache.session_cache.hostname}:${azurerm_redis_cache.session_cache.ssl_port},password=${azurerm_redis_cache.session_cache.primary_access_key},ssl=True,abortConnect=False"
}

# Resource Group for all session management resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Virtual Network for secure communication between App Service and Redis
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.virtual_network_address_space
  tags                = local.common_tags
}

# Subnet for Redis Cache with service endpoints
resource "azurerm_subnet" "redis" {
  name                 = local.subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.redis_subnet_address_prefix]
  
  # Enable service endpoints for enhanced security
  service_endpoints = ["Microsoft.Storage"]
}

# Network Security Group for Redis subnet
resource "azurerm_network_security_group" "redis" {
  name                = "nsg-${local.subnet_name}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Allow inbound Redis traffic on SSL port
  security_rule {
    name                       = "AllowRedisSSL"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6380"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Deny all other inbound traffic
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSG with Redis subnet
resource "azurerm_subnet_network_security_group_association" "redis" {
  subnet_id                 = azurerm_subnet.redis.id
  network_security_group_id = azurerm_network_security_group.redis.id
}

# Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Application Insights for application performance monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  tags                = local.common_tags
}

# Azure Managed Redis Cache for distributed session storage
resource "azurerm_redis_cache" "session_cache" {
  name                          = local.redis_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  capacity                      = var.redis_sku.capacity
  family                        = var.redis_sku.family
  sku_name                      = var.redis_sku.name
  enable_non_ssl_port           = var.enable_redis_non_ssl_port
  minimum_tls_version           = var.minimum_tls_version
  public_network_access_enabled = true
  tags                          = local.common_tags

  # Redis configuration optimized for session management
  redis_configuration {
    # LRU eviction policy for session data
    maxmemory_policy = "allkeys-lru"
    
    # Reserve memory for Redis operations
    maxmemory_reserved = 50
    
    # Reserved memory for fragmentation
    maxfragmentationmemory_reserved = 50
    
    # Enable Redis persistence for durability
    rdb_backup_enabled = true
    
    # Backup frequency (daily)
    rdb_backup_frequency = 1440
    
    # Backup retention (7 days)
    rdb_backup_max_snapshot_count = 7
  }

  # Patch schedule for maintenance
  patch_schedule {
    day_of_week    = "Sunday"
    start_hour_utc = 2
  }
}

# Redis firewall rule to allow App Service access
resource "azurerm_redis_firewall_rule" "app_service" {
  name                = "AllowAppService"
  redis_cache_name    = azurerm_redis_cache.session_cache.name
  resource_group_name = azurerm_resource_group.main.name
  start_ip            = "0.0.0.0"
  end_ip              = "255.255.255.255"
}

# App Service Plan for hosting web applications
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "${var.app_service_plan_sku.tier == "Free" || var.app_service_plan_sku.tier == "Shared" ? var.app_service_plan_sku.tier : ""}${var.app_service_plan_sku.size}"
  worker_count        = var.app_service_instances
  tags                = local.common_tags
}

# Linux Web App with .NET runtime
resource "azurerm_linux_web_app" "main" {
  name                = local.web_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true
  tags                = local.common_tags

  # Application configuration
  site_config {
    # Always on for production workloads
    always_on = var.app_service_plan_sku.tier != "Free" && var.app_service_plan_sku.tier != "Shared"
    
    # HTTP/2 support for better performance
    http2_enabled = true
    
    # Minimum TLS version for security
    minimum_tls_version = "1.2"
    
    # Application stack configuration
    application_stack {
      dotnet_version = var.dotnet_version
    }
    
    # Health check path
    health_check_path = "/health"
    
    # Enable detailed error pages for troubleshooting
    detailed_error_logging_enabled = true
    
    # Request tracing for diagnostics
    failed_request_tracing_enabled = true
  }

  # Application settings for Redis session management
  app_settings = merge({
    # Redis connection configuration
    "RedisConnection" = local.redis_connection_string
    
    # Session configuration
    "Session__IdleTimeoutMinutes" = var.session_timeout_minutes
    "Session__CookieName"        = ".AspNetCore.Session"
    "Session__CookieHttpOnly"    = "true"
    "Session__CookieSecure"      = "true"
    
    # Application Insights (if enabled)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : ""
    
    # .NET configuration
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    "ASPNETCORE_ENVIRONMENT"   = var.environment == "prod" ? "Production" : "Development"
    
    # Performance optimizations
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "WEBSITE_DYNAMIC_CACHE"        = "1"
  }, var.tags)

  # Connection strings for Entity Framework or other data access
  connection_string {
    name  = "Redis"
    type  = "Custom"
    value = local.redis_connection_string
  }

  # Enable auto-healing for improved reliability
  auto_heal_enabled = true
  
  # Identity for managed service identity
  identity {
    type = "SystemAssigned"
  }
}

# Diagnostic settings for Redis Cache
resource "azurerm_monitor_diagnostic_setting" "redis" {
  count                      = var.enable_diagnostic_logging ? 1 : 0
  name                       = "redis-diagnostics"
  target_resource_id         = azurerm_redis_cache.session_cache.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "ConnectedClientList"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for App Service
resource "azurerm_monitor_diagnostic_setting" "app_service" {
  count                      = var.enable_diagnostic_logging ? 1 : 0
  name                       = "appservice-diagnostics"
  target_resource_id         = azurerm_linux_web_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_log {
    category = "AppServiceAuditLogs"
  }

  enabled_log {
    category = "AppServiceIPSecAuditLogs"
  }

  enabled_log {
    category = "AppServicePlatformLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "session_alerts" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "SessionAlerts-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "SessAlert"
  tags                = local.common_tags

  # Email notification (placeholder - update with real email)
  email_receiver {
    name          = "admin"
    email_address = "admin@example.com"
  }
}

# Metric alert for Redis cache miss rate
resource "azurerm_monitor_metric_alert" "redis_cache_miss" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "redis-high-cache-miss-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_redis_cache.session_cache.id]
  description         = "Alert when Redis cache miss rate is high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Cache/Redis"
    metric_name      = "cachemisses"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 100
  }

  action {
    action_group_id = azurerm_monitor_action_group.session_alerts[0].id
  }
}

# Metric alert for Redis connection errors
resource "azurerm_monitor_metric_alert" "redis_connection_errors" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "redis-connection-errors-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_redis_cache.session_cache.id]
  description         = "Alert when Redis connection errors occur"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Cache/Redis"
    metric_name      = "errors"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.session_alerts[0].id
  }
}

# Metric alert for App Service response time
resource "azurerm_monitor_metric_alert" "app_service_response_time" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "app-service-slow-response-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Alert when App Service response time is high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5000  # 5 seconds
  }

  action {
    action_group_id = azurerm_monitor_action_group.session_alerts[0].id
  }
}

# Autoscaling settings for App Service Plan
resource "azurerm_monitor_autoscale_setting" "app_service" {
  count               = var.enable_monitoring && var.app_service_plan_sku.tier != "Free" && var.app_service_plan_sku.tier != "Shared" ? 1 : 0
  name                = "autoscale-${local.app_service_plan_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_service_plan.main.id
  tags                = local.common_tags

  profile {
    name = "default"

    capacity {
      default = var.app_service_instances
      minimum = 2
      maximum = 10
    }

    # Scale out rule based on CPU usage
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in rule based on CPU usage
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}