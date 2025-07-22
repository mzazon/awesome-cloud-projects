# Main Terraform configuration for Azure Web Application Performance Optimization
# This configuration deploys a complete web application performance solution using:
# - Azure App Service for hosting
# - Azure Cache for Redis for caching
# - Azure CDN for content delivery
# - Azure Database for PostgreSQL for data storage
# - Application Insights for monitoring

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming
locals {
  name_prefix = var.resource_name_prefix != "" ? "${var.resource_name_prefix}-" : ""
  name_suffix = var.resource_name_suffix != "" ? "-${var.resource_name_suffix}" : ""
  random_suffix = random_string.suffix.result
  
  # Resource names with consistent naming convention
  resource_group_name    = "${local.name_prefix}rg-${var.project_name}-${var.environment}${local.name_suffix}-${local.random_suffix}"
  app_service_plan_name  = "${local.name_prefix}asp-${var.project_name}-${var.environment}${local.name_suffix}-${local.random_suffix}"
  web_app_name          = "${local.name_prefix}webapp-${var.project_name}-${var.environment}${local.name_suffix}-${local.random_suffix}"
  redis_cache_name      = "${local.name_prefix}redis-${var.project_name}-${var.environment}${local.name_suffix}-${local.random_suffix}"
  cdn_profile_name      = "${local.name_prefix}cdn-${var.project_name}-${var.environment}${local.name_suffix}-${local.random_suffix}"
  cdn_endpoint_name     = "${local.name_prefix}cdnep-${var.project_name}-${var.environment}${local.name_suffix}-${local.random_suffix}"
  postgresql_server_name = "${local.name_prefix}psql-${var.project_name}-${var.environment}${local.name_suffix}-${local.random_suffix}"
  app_insights_name     = "${local.name_prefix}ai-${var.project_name}-${var.environment}${local.name_suffix}-${local.random_suffix}"
  log_analytics_name    = "${local.name_prefix}la-${var.project_name}-${var.environment}${local.name_suffix}-${local.random_suffix}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    DeployedBy    = "terraform"
    LastModified  = timestamp()
  })
}

# Resource Group
# Container for all resources in this deployment
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace
# Centralized logging and monitoring solution
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Application Insights
# Application performance monitoring and analytics
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = var.application_insights_type
  tags                = local.common_tags
}

# PostgreSQL Flexible Server
# Managed PostgreSQL database service for application data
resource "azurerm_postgresql_flexible_server" "main" {
  name                = local.postgresql_server_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Server configuration
  administrator_login    = var.postgresql_admin_username
  administrator_password = var.postgresql_admin_password
  version               = var.postgresql_version
  sku_name              = var.postgresql_sku_name
  storage_mb            = var.postgresql_storage_mb
  
  # Security and backup configuration
  backup_retention_days = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled     = true
  
  # High availability configuration (disabled for cost optimization in dev)
  high_availability {
    mode = "Disabled"
  }
  
  # Maintenance window configuration
  maintenance_window {
    day_of_week  = 0
    start_hour   = 2
    start_minute = 0
  }
  
  tags = local.common_tags
}

# PostgreSQL Database
# Application database within the PostgreSQL server
resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# PostgreSQL Firewall Rules
# Allow access from Azure services and specified IP addresses
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Additional firewall rules for specified IP addresses
resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed_ips" {
  count            = length(var.allowed_ip_addresses)
  name             = "AllowedIP${count.index}"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = var.allowed_ip_addresses[count.index]
  end_ip_address   = var.allowed_ip_addresses[count.index]
}

# Azure Cache for Redis
# High-performance in-memory cache for application data
resource "azurerm_redis_cache" "main" {
  name                = local.redis_cache_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Cache configuration
  capacity            = tonumber(regex("\\d+", var.redis_cache_size))
  family              = startswith(var.redis_cache_size, "P") ? "P" : "C"
  sku_name            = var.redis_cache_sku
  enable_non_ssl_port = var.redis_enable_non_ssl_port
  minimum_tls_version = "1.2"
  
  # Redis configuration
  redis_configuration {
    maxmemory_policy                = var.redis_maxmemory_policy
    maxmemory_reserved              = var.redis_cache_sku == "Premium" ? 2 : 0
    maxmemory_delta                 = var.redis_cache_sku == "Premium" ? 2 : 0
    maxfragmentationmemory_reserved = var.redis_cache_sku == "Premium" ? 2 : 0
  }
  
  # Patch schedule for maintenance (weekends)
  patch_schedule {
    day_of_week    = "Saturday"
    start_hour_utc = 2
  }
  
  tags = local.common_tags
}

# App Service Plan
# Hosting plan for the web application
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Plan configuration
  os_type  = "Linux"
  sku_name = var.app_service_plan_sku
  
  tags = local.common_tags
}

# App Service (Web App)
# Web application hosting service
resource "azurerm_linux_web_app" "main" {
  name                = local.web_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  # HTTPS and security configuration
  https_only                    = var.enable_https_only
  public_network_access_enabled = true
  
  # Application settings
  app_settings = {
    # Redis connection settings
    REDIS_HOSTNAME = azurerm_redis_cache.main.hostname
    REDIS_KEY      = azurerm_redis_cache.main.primary_access_key
    REDIS_PORT     = "6380"
    REDIS_SSL      = "true"
    
    # Database connection settings
    DATABASE_URL = "postgresql://${var.postgresql_admin_username}:${var.postgresql_admin_password}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.database_name}?sslmode=require"
    
    # Application Insights settings
    APPINSIGHTS_INSTRUMENTATIONKEY        = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : ""
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : ""
    
    # Node.js specific settings
    WEBSITE_NODE_DEFAULT_VERSION = "18-lts"
    NODE_ENV                     = var.environment
    
    # Performance optimization settings
    WEBSITE_ENABLE_SYNC_UPDATE_SITE = "true"
    WEBSITE_RUN_FROM_PACKAGE       = "1"
  }
  
  # Site configuration
  site_config {
    # Runtime configuration
    application_stack {
      node_version = "18-lts"
    }
    
    # Performance and security settings
    always_on        = var.app_service_always_on
    ftps_state       = "Disabled"
    http2_enabled    = true
    minimum_tls_version = var.min_tls_version
    
    # CORS configuration for web applications
    cors {
      allowed_origins = ["*"]
      support_credentials = false
    }
  }
  
  # Connection strings for database
  connection_string {
    name  = "DefaultConnection"
    type  = "PostgreSQL"
    value = "Server=${azurerm_postgresql_flexible_server.main.fqdn};Database=${var.database_name};Port=5432;User Id=${var.postgresql_admin_username};Password=${var.postgresql_admin_password};Ssl Mode=Require;"
  }
  
  tags = local.common_tags
  
  # Ensure dependencies are created first
  depends_on = [
    azurerm_redis_cache.main,
    azurerm_postgresql_flexible_server.main,
    azurerm_postgresql_flexible_server_database.main
  ]
}

# Diagnostic Settings for Web App
# Enable diagnostic logging for the web application
resource "azurerm_monitor_diagnostic_setting" "web_app" {
  count              = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  name               = "webapp-diagnostics"
  target_resource_id = azurerm_linux_web_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable application logs
  enabled_log {
    category = "AppServiceHTTPLogs"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "AppServiceConsoleLogs"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "AppServiceAppLogs"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  # Enable performance metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# CDN Profile
# Content Delivery Network profile for global content distribution
resource "azurerm_cdn_profile" "main" {
  name                = local.cdn_profile_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.cdn_profile_sku
  tags                = local.common_tags
}

# CDN Endpoint
# CDN endpoint for caching and delivering web application content
resource "azurerm_cdn_endpoint" "main" {
  name                = local.cdn_endpoint_name
  profile_name        = azurerm_cdn_profile.main.name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Origin configuration pointing to the web app
  origin {
    name      = "webapp-origin"
    host_name = azurerm_linux_web_app.main.default_hostname
  }
  
  # CDN configuration
  is_compression_enabled = var.cdn_enable_compression
  content_types_to_compress = [
    "text/plain",
    "text/html",
    "text/css",
    "text/javascript",
    "application/x-javascript",
    "application/javascript",
    "application/json",
    "application/xml"
  ]
  
  # Query string caching behavior
  querystring_caching_behaviour = var.cdn_query_string_caching
  
  # Origin host header
  origin_host_header = azurerm_linux_web_app.main.default_hostname
  
  # Caching rules for different content types
  delivery_rule {
    name  = "StaticAssetsCaching"
    order = 1
    
    # Match static assets
    request_uri_condition {
      operator     = "BeginsWith"
      match_values = ["/static/", "/images/", "/css/", "/js/", "/assets/"]
    }
    
    # Cache for 30 days
    cache_expiration_action {
      behavior = "Override"
      duration = "30.00:00:00"
    }
    
    # Enable compression
    response_header_action {
      action        = "Append"
      header_name   = "Cache-Control"
      header_value  = "public, max-age=2592000"
    }
  }
  
  delivery_rule {
    name  = "APIEndpointsCaching"
    order = 2
    
    # Match API endpoints
    request_uri_condition {
      operator     = "BeginsWith"
      match_values = ["/api/"]
    }
    
    # Cache for 5 minutes
    cache_expiration_action {
      behavior = "Override"
      duration = "0.00:05:00"
    }
    
    # Add cache headers
    response_header_action {
      action        = "Append"
      header_name   = "Cache-Control"
      header_value  = "public, max-age=300"
    }
  }
  
  delivery_rule {
    name  = "DefaultCaching"
    order = 3
    
    # Match all other content
    request_uri_condition {
      operator     = "BeginsWith"
      match_values = ["/"]
    }
    
    # Cache for 1 hour
    cache_expiration_action {
      behavior = "Override"
      duration = "0.01:00:00"
    }
  }
  
  # Global delivery rule for security headers
  global_delivery_rule {
    # Add security headers
    response_header_action {
      action        = "Append"
      header_name   = "X-Content-Type-Options"
      header_value  = "nosniff"
    }
    
    response_header_action {
      action        = "Append"
      header_name   = "X-Frame-Options"
      header_value  = "SAMEORIGIN"
    }
    
    response_header_action {
      action        = "Append"
      header_name   = "X-XSS-Protection"
      header_value  = "1; mode=block"
    }
  }
  
  tags = local.common_tags
  
  depends_on = [azurerm_linux_web_app.main]
}

# Diagnostic Settings for CDN
# Enable diagnostic logging for CDN endpoint
resource "azurerm_monitor_diagnostic_setting" "cdn_endpoint" {
  count              = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  name               = "cdn-diagnostics"
  target_resource_id = azurerm_cdn_endpoint.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable CDN access logs
  enabled_log {
    category = "CoreAnalytics"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  # Enable performance metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Diagnostic Settings for Redis Cache
# Enable diagnostic logging for Redis cache
resource "azurerm_monitor_diagnostic_setting" "redis_cache" {
  count              = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  name               = "redis-diagnostics"
  target_resource_id = azurerm_redis_cache.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable Redis connection logs
  enabled_log {
    category = "ConnectedClientList"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  # Enable performance metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Diagnostic Settings for PostgreSQL
# Enable diagnostic logging for PostgreSQL server
resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  count              = var.enable_diagnostic_logs && var.enable_monitoring ? 1 : 0
  name               = "postgresql-diagnostics"
  target_resource_id = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  # Enable PostgreSQL logs
  enabled_log {
    category = "PostgreSQLLogs"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  # Enable performance metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}