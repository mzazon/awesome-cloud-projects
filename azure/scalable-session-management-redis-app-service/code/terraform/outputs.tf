# Outputs for Azure distributed session management infrastructure
# These outputs provide essential information for application deployment and monitoring

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Redis Cache Information
output "redis_cache_name" {
  description = "Name of the Azure Redis Cache instance"
  value       = azurerm_redis_cache.session_cache.name
}

output "redis_hostname" {
  description = "Hostname of the Redis Cache instance"
  value       = azurerm_redis_cache.session_cache.hostname
}

output "redis_ssl_port" {
  description = "SSL port for Redis Cache connections"
  value       = azurerm_redis_cache.session_cache.ssl_port
}

output "redis_port" {
  description = "Non-SSL port for Redis Cache connections (if enabled)"
  value       = azurerm_redis_cache.session_cache.port
}

output "redis_primary_access_key" {
  description = "Primary access key for Redis Cache"
  value       = azurerm_redis_cache.session_cache.primary_access_key
  sensitive   = true
}

output "redis_secondary_access_key" {
  description = "Secondary access key for Redis Cache"
  value       = azurerm_redis_cache.session_cache.secondary_access_key
  sensitive   = true
}

output "redis_connection_string" {
  description = "Complete Redis connection string for application configuration"
  value       = local.redis_connection_string
  sensitive   = true
}

# App Service Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "web_app_name" {
  description = "Name of the web application"
  value       = azurerm_linux_web_app.main.name
}

output "web_app_default_hostname" {
  description = "Default hostname of the web application"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "web_app_url" {
  description = "Full HTTPS URL of the web application"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "web_app_id" {
  description = "ID of the web application"
  value       = azurerm_linux_web_app.main.id
}

output "web_app_kind" {
  description = "Kind of the web application"
  value       = azurerm_linux_web_app.main.kind
}

output "web_app_outbound_ip_addresses" {
  description = "Outbound IP addresses of the web application"
  value       = azurerm_linux_web_app.main.outbound_ip_addresses
}

output "web_app_possible_outbound_ip_addresses" {
  description = "Possible outbound IP addresses of the web application"
  value       = azurerm_linux_web_app.main.possible_outbound_ip_addresses
}

# Managed Identity Information
output "web_app_principal_id" {
  description = "Principal ID of the web application's managed identity"
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

output "web_app_tenant_id" {
  description = "Tenant ID of the web application's managed identity"
  value       = azurerm_linux_web_app.main.identity[0].tenant_id
}

# Networking Information
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "redis_subnet_name" {
  description = "Name of the Redis subnet"
  value       = azurerm_subnet.redis.name
}

output "redis_subnet_id" {
  description = "ID of the Redis subnet"
  value       = azurerm_subnet.redis.id
}

# Monitoring Information (conditional outputs based on monitoring enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "application_insights_name" {
  description = "Name of the Application Insights instance (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "action_group_name" {
  description = "Name of the monitoring action group (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.session_alerts[0].name : null
}

# Configuration Information
output "session_configuration" {
  description = "Session management configuration summary"
  value = {
    timeout_minutes = var.session_timeout_minutes
    redis_sku      = var.redis_sku
    app_instances  = var.app_service_instances
    environment    = var.environment
  }
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources for verification"
  value = {
    resource_group        = azurerm_resource_group.main.name
    redis_cache          = azurerm_redis_cache.session_cache.name
    web_application      = azurerm_linux_web_app.main.name
    app_service_plan     = azurerm_service_plan.main.name
    virtual_network      = azurerm_virtual_network.main.name
    monitoring_enabled   = var.enable_monitoring
    diagnostic_enabled   = var.enable_diagnostic_logging
    created_timestamp    = timestamp()
  }
}

# Security Configuration
output "security_configuration" {
  description = "Security settings summary"
  value = {
    redis_ssl_only        = !var.enable_redis_non_ssl_port
    minimum_tls_version   = var.minimum_tls_version
    https_only           = azurerm_linux_web_app.main.https_only
    managed_identity     = "SystemAssigned"
  }
}

# Cost Estimation Guidance
output "cost_estimation_guidance" {
  description = "Guidance for cost estimation based on deployed resources"
  value = {
    redis_sku              = "${var.redis_sku.name} (${var.redis_sku.family}${var.redis_sku.capacity})"
    app_service_plan_sku   = "${var.app_service_plan_sku.tier} ${var.app_service_plan_sku.size}"
    instance_count         = var.app_service_instances
    estimated_monthly_cost = "~$75-100 USD (varies by region and usage)"
  }
}

# Troubleshooting Information
output "troubleshooting_endpoints" {
  description = "Key endpoints for troubleshooting and monitoring"
  value = {
    web_app_scm_url    = "https://${azurerm_linux_web_app.main.name}.scm.azurewebsites.net"
    web_app_health_url = "https://${azurerm_linux_web_app.main.default_hostname}/health"
    redis_hostname     = azurerm_redis_cache.session_cache.hostname
    redis_port         = azurerm_redis_cache.session_cache.ssl_port
  }
}