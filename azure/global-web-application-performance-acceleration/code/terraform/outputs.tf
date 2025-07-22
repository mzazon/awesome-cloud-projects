# Outputs for Azure Web Application Performance Optimization
# This file defines all outputs that will be displayed after deployment
# and can be used by other Terraform configurations or CI/CD pipelines

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Web Application Information
output "web_app_name" {
  description = "Name of the Azure Web App"
  value       = azurerm_linux_web_app.main.name
}

output "web_app_url" {
  description = "URL of the Azure Web App"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "web_app_default_hostname" {
  description = "Default hostname of the Azure Web App"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "web_app_id" {
  description = "ID of the Azure Web App"
  value       = azurerm_linux_web_app.main.id
}

output "web_app_identity_principal_id" {
  description = "Principal ID of the Web App's managed identity"
  value       = azurerm_linux_web_app.main.identity != null ? azurerm_linux_web_app.main.identity[0].principal_id : null
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Redis Cache Information
output "redis_cache_name" {
  description = "Name of the Redis Cache"
  value       = azurerm_redis_cache.main.name
}

output "redis_cache_hostname" {
  description = "Hostname of the Redis Cache"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_cache_port" {
  description = "Port of the Redis Cache"
  value       = azurerm_redis_cache.main.port
}

output "redis_cache_ssl_port" {
  description = "SSL port of the Redis Cache"
  value       = azurerm_redis_cache.main.ssl_port
}

output "redis_cache_primary_access_key" {
  description = "Primary access key for the Redis Cache"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

output "redis_cache_secondary_access_key" {
  description = "Secondary access key for the Redis Cache"
  value       = azurerm_redis_cache.main.secondary_access_key
  sensitive   = true
}

output "redis_cache_id" {
  description = "ID of the Redis Cache"
  value       = azurerm_redis_cache.main.id
}

# CDN Information
output "cdn_profile_name" {
  description = "Name of the CDN Profile"
  value       = azurerm_cdn_profile.main.name
}

output "cdn_profile_id" {
  description = "ID of the CDN Profile"
  value       = azurerm_cdn_profile.main.id
}

output "cdn_endpoint_name" {
  description = "Name of the CDN Endpoint"
  value       = azurerm_cdn_endpoint.main.name
}

output "cdn_endpoint_url" {
  description = "URL of the CDN Endpoint"
  value       = "https://${azurerm_cdn_endpoint.main.fqdn}"
}

output "cdn_endpoint_fqdn" {
  description = "FQDN of the CDN Endpoint"
  value       = azurerm_cdn_endpoint.main.fqdn
}

output "cdn_endpoint_id" {
  description = "ID of the CDN Endpoint"
  value       = azurerm_cdn_endpoint.main.id
}

# Database Information
output "postgresql_server_name" {
  description = "Name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "postgresql_server_fqdn" {
  description = "FQDN of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgresql_server_id" {
  description = "ID of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.id
}

output "postgresql_database_name" {
  description = "Name of the PostgreSQL database"
  value       = azurerm_postgresql_flexible_server_database.main.name
}

output "postgresql_connection_string" {
  description = "Connection string for the PostgreSQL database"
  value       = "Server=${azurerm_postgresql_flexible_server.main.fqdn};Database=${azurerm_postgresql_flexible_server_database.main.name};Port=5432;User Id=${var.postgresql_admin_username};Password=${var.postgresql_admin_password};Ssl Mode=Require;"
  sensitive   = true
}

output "postgresql_admin_username" {
  description = "Administrator username for PostgreSQL"
  value       = azurerm_postgresql_flexible_server.main.administrator_login
}

# Monitoring Information
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID of Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].app_id : null
}

output "application_insights_id" {
  description = "ID of the Application Insights resource"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].id : null
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].primary_shared_key : null
  sensitive   = true
}

# Environment Configuration
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "location" {
  description = "Azure region location"
  value       = var.location
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

# Performance Optimization URLs
output "performance_test_urls" {
  description = "URLs for performance testing"
  value = {
    web_app_direct = "https://${azurerm_linux_web_app.main.default_hostname}"
    cdn_endpoint   = "https://${azurerm_cdn_endpoint.main.fqdn}"
    api_direct     = "https://${azurerm_linux_web_app.main.default_hostname}/api/"
    api_via_cdn    = "https://${azurerm_cdn_endpoint.main.fqdn}/api/"
    static_direct  = "https://${azurerm_linux_web_app.main.default_hostname}/static/"
    static_via_cdn = "https://${azurerm_cdn_endpoint.main.fqdn}/static/"
  }
}

# Connection Information for Application Configuration
output "application_config" {
  description = "Configuration values for the application"
  value = {
    redis_hostname = azurerm_redis_cache.main.hostname
    redis_port     = azurerm_redis_cache.main.ssl_port
    redis_ssl      = true
    database_host  = azurerm_postgresql_flexible_server.main.fqdn
    database_port  = 5432
    database_name  = azurerm_postgresql_flexible_server_database.main.name
    database_ssl   = true
    cdn_endpoint   = azurerm_cdn_endpoint.main.fqdn
  }
  sensitive = false
}

# Security Information
output "security_config" {
  description = "Security configuration details"
  value = {
    https_only              = var.enable_https_only
    min_tls_version        = var.min_tls_version
    redis_ssl_enabled      = !var.redis_enable_non_ssl_port
    database_ssl_required  = true
    cdn_https_enabled      = true
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information about cost optimization features"
  value = {
    app_service_plan_tier = var.app_service_plan_sku
    redis_cache_tier      = var.redis_cache_sku
    redis_cache_size      = var.redis_cache_size
    cdn_profile_sku       = var.cdn_profile_sku
    postgresql_sku        = var.postgresql_sku_name
    monitoring_enabled    = var.enable_monitoring
  }
}

# Networking Information
output "networking_info" {
  description = "Networking configuration details"
  value = {
    resource_group_location = azurerm_resource_group.main.location
    web_app_outbound_ips   = azurerm_linux_web_app.main.outbound_ip_addresses
    web_app_possible_outbound_ips = azurerm_linux_web_app.main.possible_outbound_ip_addresses
  }
}

# Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring and management"
  value = var.enable_monitoring ? {
    application_insights = "https://portal.azure.com/#resource${azurerm_application_insights.main[0].id}"
    log_analytics       = "https://portal.azure.com/#resource${azurerm_log_analytics_workspace.main[0].id}"
    web_app_metrics     = "https://portal.azure.com/#resource${azurerm_linux_web_app.main.id}/metrics"
    redis_metrics       = "https://portal.azure.com/#resource${azurerm_redis_cache.main.id}/metrics"
    cdn_analytics       = "https://portal.azure.com/#resource${azurerm_cdn_endpoint.main.id}/analytics"
  } : null
}

# Tags Applied
output "tags_applied" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}

# Resource Counts
output "resource_summary" {
  description = "Summary of resources created"
  value = {
    resource_group_count       = 1
    web_app_count             = 1
    app_service_plan_count    = 1
    redis_cache_count         = 1
    cdn_profile_count         = 1
    cdn_endpoint_count        = 1
    postgresql_server_count   = 1
    postgresql_database_count = 1
    application_insights_count = var.enable_monitoring ? 1 : 0
    log_analytics_count       = var.enable_monitoring ? 1 : 0
    diagnostic_settings_count = var.enable_diagnostic_logs && var.enable_monitoring ? 4 : 0
  }
}