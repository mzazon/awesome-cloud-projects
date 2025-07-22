# Outputs for Enterprise API Protection Infrastructure
# This file defines all the output values that are useful for verification,
# integration, and operational purposes

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Random Suffix for Reference
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# API Management Information
output "api_management_name" {
  description = "Name of the API Management instance"
  value       = azurerm_api_management.main.name
}

output "api_management_gateway_url" {
  description = "Gateway URL for API Management"
  value       = azurerm_api_management.main.gateway_url
}

output "api_management_developer_portal_url" {
  description = "Developer portal URL for API Management"
  value       = azurerm_api_management.main.developer_portal_url
}

output "api_management_management_api_url" {
  description = "Management API URL for API Management"
  value       = azurerm_api_management.main.management_api_url
}

output "api_management_portal_url" {
  description = "Publisher portal URL for API Management"
  value       = azurerm_api_management.main.portal_url
}

output "api_management_principal_id" {
  description = "Principal ID of the API Management managed identity"
  value       = azurerm_api_management.main.identity[0].principal_id
}

output "api_management_public_ip_addresses" {
  description = "Public IP addresses of API Management"
  value       = azurerm_api_management.main.public_ip_addresses
}

# Sample API Information
output "sample_api_name" {
  description = "Name of the sample API"
  value       = azurerm_api_management_api.sample.name
}

output "sample_api_path" {
  description = "Path of the sample API"
  value       = azurerm_api_management_api.sample.path
}

output "sample_api_service_url" {
  description = "Backend service URL for the sample API"
  value       = azurerm_api_management_api.sample.service_url
}

# API Subscription Information
output "api_subscription_id" {
  description = "ID of the API subscription"
  value       = azurerm_api_management_subscription.sample.id
}

output "api_subscription_primary_key" {
  description = "Primary key for API subscription"
  value       = azurerm_api_management_subscription.sample.primary_key
  sensitive   = true
}

output "api_subscription_secondary_key" {
  description = "Secondary key for API subscription"
  value       = azurerm_api_management_subscription.sample.secondary_key
  sensitive   = true
}

# Redis Cache Information
output "redis_cache_name" {
  description = "Name of the Redis cache"
  value       = azurerm_redis_cache.main.name
}

output "redis_cache_hostname" {
  description = "Hostname of the Redis cache"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_cache_ssl_port" {
  description = "SSL port of the Redis cache"
  value       = azurerm_redis_cache.main.ssl_port
}

output "redis_cache_port" {
  description = "Non-SSL port of the Redis cache"
  value       = azurerm_redis_cache.main.port
}

output "redis_primary_access_key" {
  description = "Primary access key for Redis cache"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

output "redis_secondary_access_key" {
  description = "Secondary access key for Redis cache"
  value       = azurerm_redis_cache.main.secondary_access_key
  sensitive   = true
}

output "redis_primary_connection_string" {
  description = "Primary connection string for Redis cache"
  value       = azurerm_redis_cache.main.primary_connection_string
  sensitive   = true
}

output "redis_secondary_connection_string" {
  description = "Secondary connection string for Redis cache"
  value       = azurerm_redis_cache.main.secondary_connection_string
  sensitive   = true
}

# Front Door Information
output "front_door_profile_name" {
  description = "Name of the Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.main.name
}

output "front_door_endpoint_name" {
  description = "Name of the Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.main.name
}

output "front_door_endpoint_hostname" {
  description = "Hostname of the Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.main.host_name
}

output "front_door_endpoint_url" {
  description = "Full URL of the Front Door endpoint"
  value       = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
}

# WAF Policy Information
output "waf_policy_name" {
  description = "Name of the WAF policy"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.name
}

output "waf_policy_id" {
  description = "ID of the WAF policy"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.id
}

output "waf_policy_mode" {
  description = "Mode of the WAF policy"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.mode
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "App ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "log_analytics_secondary_shared_key" {
  description = "Secondary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.secondary_shared_key
  sensitive   = true
}

# Monitoring Information
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = azurerm_monitor_action_group.main.id
}

# Security Information
output "api_management_identity_principal_id" {
  description = "Principal ID of the API Management managed identity"
  value       = azurerm_api_management.main.identity[0].principal_id
}

output "api_management_identity_tenant_id" {
  description = "Tenant ID of the API Management managed identity"
  value       = azurerm_api_management.main.identity[0].tenant_id
}

# Testing and Verification URLs
output "api_test_url" {
  description = "URL for testing the API through Front Door"
  value       = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}${var.sample_api_path}/get"
}

output "api_direct_test_url" {
  description = "Direct URL for testing the API through API Management"
  value       = "${azurerm_api_management.main.gateway_url}${var.sample_api_path}/get"
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    api_management = {
      name         = azurerm_api_management.main.name
      gateway_url  = azurerm_api_management.main.gateway_url
      sku          = "${var.apim_sku_name}_${var.apim_sku_capacity}"
      identity_id  = azurerm_api_management.main.identity[0].principal_id
    }
    front_door = {
      name     = azurerm_cdn_frontdoor_profile.main.name
      endpoint = azurerm_cdn_frontdoor_endpoint.main.host_name
      url      = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
      sku      = var.front_door_sku
    }
    waf = {
      name   = azurerm_cdn_frontdoor_firewall_policy.main.name
      mode   = azurerm_cdn_frontdoor_firewall_policy.main.mode
      status = azurerm_cdn_frontdoor_firewall_policy.main.enabled
    }
    redis = {
      name     = azurerm_redis_cache.main.name
      hostname = azurerm_redis_cache.main.hostname
      port     = azurerm_redis_cache.main.ssl_port
      sku      = "${var.redis_sku}_P${var.redis_capacity}"
    }
    monitoring = {
      app_insights        = azurerm_application_insights.main.name
      log_analytics      = azurerm_log_analytics_workspace.main.name
      action_group       = azurerm_monitor_action_group.main.name
    }
  }
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = var.common_tags
}

# Network and Security Configuration
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    tls_version              = var.minimum_tls_version
    managed_identity_enabled = var.enable_managed_identity
    waf_mode                = var.waf_mode
    ssl_only                = true
    rate_limit_calls        = var.rate_limit_calls
    rate_limit_period       = var.rate_limit_renewal_period
    quota_calls             = var.quota_calls
    quota_period            = var.quota_renewal_period
    cache_duration          = var.cache_duration
  }
}

# Cost and Performance Information
output "performance_configuration" {
  description = "Performance configuration summary"
  value = {
    api_management_capacity = var.apim_sku_capacity
    redis_capacity         = var.redis_capacity
    cache_policy           = var.redis_maxmemory_policy
    health_probe_interval  = var.health_probe_interval
    front_door_sku         = var.front_door_sku
  }
}

# Troubleshooting Information
output "troubleshooting_endpoints" {
  description = "Endpoints for troubleshooting and verification"
  value = {
    api_management_status = "${azurerm_api_management.main.gateway_url}/status-0123456789abcdef"
    front_door_health     = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}${var.health_probe_path}"
    redis_info           = "Use Redis CLI: redis-cli -h ${azurerm_redis_cache.main.hostname} -p ${azurerm_redis_cache.main.ssl_port} --tls"
  }
}

# Documentation URLs
output "documentation_urls" {
  description = "Relevant Azure documentation URLs"
  value = {
    api_management = "https://docs.microsoft.com/en-us/azure/api-management/"
    front_door     = "https://docs.microsoft.com/en-us/azure/frontdoor/"
    waf            = "https://docs.microsoft.com/en-us/azure/web-application-firewall/"
    redis          = "https://docs.microsoft.com/en-us/azure/azure-cache-for-redis/"
    app_insights   = "https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview"
  }
}