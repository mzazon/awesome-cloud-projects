# Core infrastructure outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# API Management outputs
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

output "api_management_principal_id" {
  description = "Principal ID of the API Management managed identity"
  value       = var.enable_managed_identity ? azurerm_api_management.main.identity[0].principal_id : null
  sensitive   = false
}

output "api_management_regions" {
  description = "List of all regions where API Management is deployed"
  value = concat(
    [var.location],
    var.secondary_regions
  )
}

output "api_management_regional_endpoints" {
  description = "Regional endpoints for API Management"
  value = {
    primary = azurerm_api_management.main.gateway_url
    secondary = [
      for i, region in var.secondary_regions :
      "https://${azurerm_api_management.main.name}-${replace(lower(region), " ", "")}-01.regional.azure-api.net"
    ]
  }
}

# Cosmos DB outputs
output "cosmos_db_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_db_endpoint" {
  description = "Cosmos DB endpoint URL"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_primary_key" {
  description = "Cosmos DB primary master key"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "cosmos_db_connection_strings" {
  description = "Cosmos DB connection strings"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}

output "cosmos_db_write_endpoints" {
  description = "Cosmos DB write endpoints by region"
  value       = azurerm_cosmosdb_account.main.write_endpoints
}

output "cosmos_db_read_endpoints" {
  description = "Cosmos DB read endpoints by region"
  value       = azurerm_cosmosdb_account.main.read_endpoints
}

output "cosmos_db_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.api_configuration.name
}

output "cosmos_db_containers" {
  description = "Cosmos DB container information"
  value = {
    rate_limits = {
      name           = azurerm_cosmosdb_sql_container.rate_limits.name
      partition_key  = azurerm_cosmosdb_sql_container.rate_limits.partition_key_path
      throughput     = azurerm_cosmosdb_sql_container.rate_limits.throughput
    }
    api_config = {
      name           = azurerm_cosmosdb_sql_container.api_config.name
      partition_key  = azurerm_cosmosdb_sql_container.api_config.partition_key_path
      throughput     = azurerm_cosmosdb_sql_container.api_config.throughput
    }
  }
}

# Traffic Manager outputs
output "traffic_manager_profile_name" {
  description = "Name of the Traffic Manager profile"
  value       = azurerm_traffic_manager_profile.main.name
}

output "traffic_manager_dns_name" {
  description = "DNS name for the Traffic Manager profile"
  value       = azurerm_traffic_manager_profile.main.fqdn
}

output "traffic_manager_endpoints" {
  description = "Traffic Manager endpoint configuration"
  value = {
    primary = {
      name     = azurerm_traffic_manager_azure_endpoint.primary.name
      priority = azurerm_traffic_manager_azure_endpoint.primary.priority
      weight   = azurerm_traffic_manager_azure_endpoint.primary.weight
    }
    secondary = [
      for endpoint in azurerm_traffic_manager_external_endpoint.secondary :
      {
        name     = endpoint.name
        target   = endpoint.target
        priority = endpoint.priority
        weight   = endpoint.weight
      }
    ]
  }
}

output "global_api_endpoint" {
  description = "Global API endpoint URL via Traffic Manager"
  value       = "https://${azurerm_traffic_manager_profile.main.fqdn}"
}

# Monitoring outputs
output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : null
}

# Sample API outputs
output "sample_api_details" {
  description = "Details of the created sample API"
  value = {
    name         = azurerm_api_management_api.weather_api.name
    display_name = azurerm_api_management_api.weather_api.display_name
    path         = azurerm_api_management_api.weather_api.path
    api_url      = "${azurerm_api_management.main.gateway_url}/${azurerm_api_management_api.weather_api.path}"
  }
}

# Security and configuration outputs
output "managed_identity_enabled" {
  description = "Whether managed identity is enabled"
  value       = var.enable_managed_identity
}

output "multi_region_writes_enabled" {
  description = "Whether Cosmos DB multi-region writes are enabled"
  value       = var.cosmos_enable_multi_region_writes
}

output "zone_redundancy_enabled" {
  description = "Whether zone redundancy is enabled for API Management"
  value       = var.apim_enable_zone_redundancy
}

# Deployment information
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    total_regions              = length(var.secondary_regions) + 1
    primary_region            = var.location
    secondary_regions         = var.secondary_regions
    api_management_sku        = var.apim_sku_name
    cosmos_db_consistency     = var.cosmos_consistency_level
    traffic_manager_routing   = var.traffic_manager_routing_method
    monitoring_enabled        = var.enable_application_insights
    managed_identity_enabled  = var.enable_managed_identity
  }
}

# Connection information for applications
output "connection_info" {
  description = "Connection information for applications"
  value = {
    global_api_endpoint = "https://${azurerm_traffic_manager_profile.main.fqdn}"
    primary_api_endpoint = azurerm_api_management.main.gateway_url
    cosmos_db_endpoint = azurerm_cosmosdb_account.main.endpoint
    sample_api_path = "/${azurerm_api_management_api.weather_api.path}/weather"
    health_check_path = "/status-0123456789abcdef"
  }
  sensitive = false
}

# Cost optimization information
output "cost_optimization_notes" {
  description = "Notes for cost optimization"
  value = {
    api_management_capacity = "Current capacity: ${var.apim_sku_capacity} units per region"
    cosmos_db_throughput = "Current throughput: ${var.cosmos_throughput} RU/s for rate limits container"
    log_retention = "Log retention: ${var.log_retention_days} days"
    recommendations = [
      "Consider using autoscale for Cosmos DB containers based on usage patterns",
      "Review API Management capacity requirements periodically",
      "Use reserved capacity for predictable workloads",
      "Monitor unused API Management features and disable if not needed"
    ]
  }
}