# Output values for the Azure Service Discovery Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account containing Azure Tables"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

# Service Registry Tables
output "service_registry_tables" {
  description = "List of created service registry table names"
  value       = azurerm_storage_table.service_registry[*].name
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App for health monitoring"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's system-assigned identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_urls" {
  description = "Important Function App endpoint URLs"
  value = {
    service_registration_url = "https://${azurerm_linux_function_app.main.default_hostname}/api/ServiceRegistrar"
    service_discovery_url    = "https://${azurerm_linux_function_app.main.default_hostname}/api/ServiceDiscovery"
    health_monitor_url       = "https://${azurerm_linux_function_app.main.default_hostname}/api/HealthMonitor"
  }
}

# Web App Information
output "web_app_name" {
  description = "Name of the Web App for service discovery demonstration"
  value       = azurerm_linux_web_app.main.name
}

output "web_app_default_hostname" {
  description = "Default hostname of the Web App"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "web_app_url" {
  description = "URL of the Web App"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "web_app_principal_id" {
  description = "Principal ID of the Web App's system-assigned identity"
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# SQL Server Information
output "sql_server_name" {
  description = "Name of the SQL Server"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the SQL Database"
  value       = azurerm_mssql_database.main.name
}

output "sql_connection_string" {
  description = "SQL Server connection string"
  value       = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main.name};Persist Security Info=False;User ID=${var.sql_server_admin_username};Password=${local.sql_admin_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sensitive   = true
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

output "redis_cache_ssl_port" {
  description = "SSL port of the Redis Cache"
  value       = azurerm_redis_cache.main.ssl_port
}

output "redis_primary_access_key" {
  description = "Primary access key for the Redis Cache"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

output "redis_connection_string" {
  description = "Redis Cache connection string"
  value       = "${azurerm_redis_cache.main.hostname}:${azurerm_redis_cache.main.ssl_port},password=${azurerm_redis_cache.main.primary_access_key},ssl=True,abortConnect=False"
  sensitive   = true
}

# Service Bus Information
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_connection_string" {
  description = "Service Bus namespace connection string"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "service_bus_queue_name" {
  description = "Name of the Service Bus queue"
  value       = azurerm_servicebus_queue.main.name
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_secret_names" {
  description = "Names of secrets stored in Key Vault"
  value = [
    azurerm_key_vault_secret.sql_connection_string.name,
    azurerm_key_vault_secret.redis_connection_string.name,
    azurerm_key_vault_secret.servicebus_connection_string.name
  ]
}

# Application Insights Information (conditional)
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Service Connector Information
output "service_connector_names" {
  description = "Names of the created Service Connector connections"
  value = {
    function_to_storage     = azurerm_app_service_connection.function_to_storage.name
    webapp_to_storage       = azurerm_app_service_connection.webapp_to_storage.name
    webapp_to_sql          = azurerm_app_service_connection.webapp_to_sql.name
    webapp_to_redis        = azurerm_app_service_connection.webapp_to_redis.name
    webapp_to_servicebus   = azurerm_app_service_connection.webapp_to_servicebus.name
    function_to_keyvault   = azurerm_app_service_connection.function_to_keyvault.name
  }
}

# Deployment Information
output "deployment_info" {
  description = "Summary of deployed resources and configuration"
  value = {
    environment           = var.environment
    project_name         = var.project_name
    resource_group_name  = azurerm_resource_group.main.name
    location             = azurerm_resource_group.main.location
    random_suffix        = random_string.suffix.result
    monitoring_enabled   = var.enable_monitoring
    logging_enabled      = var.enable_logging
    tables_created       = length(azurerm_storage_table.service_registry)
    service_connectors   = 6
  }
}

# Quick Start Information
output "quick_start_info" {
  description = "Quick start commands and URLs for testing the service discovery system"
  value = {
    test_service_registration = "curl -X POST 'https://${azurerm_linux_function_app.main.default_hostname}/api/ServiceRegistrar' -H 'Content-Type: application/json' -d '{\"serviceName\": \"test-api\", \"endpoint\": \"https://test-api.example.com\", \"serviceType\": \"api\"}'"
    test_service_discovery   = "curl 'https://${azurerm_linux_function_app.main.default_hostname}/api/ServiceDiscovery'"
    web_app_url             = "https://${azurerm_linux_web_app.main.default_hostname}"
    storage_account_name    = azurerm_storage_account.main.name
    resource_group_name     = azurerm_resource_group.main.name
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information about cost optimization and resource management"
  value = {
    app_service_plan_sku    = azurerm_service_plan.main.sku_name
    sql_database_sku        = azurerm_mssql_database.main.sku_name
    redis_sku               = "${azurerm_redis_cache.main.sku_name}_${azurerm_redis_cache.main.family}${azurerm_redis_cache.main.capacity}"
    storage_tier            = azurerm_storage_account.main.account_tier
    storage_replication     = azurerm_storage_account.main.account_replication_type
    monitoring_cost_impact  = var.enable_monitoring ? "Application Insights charges apply" : "No Application Insights costs"
  }
}

# Security Information
output "security_info" {
  description = "Security configuration summary"
  value = {
    storage_https_only      = azurerm_storage_account.main.enable_https_traffic_only
    storage_min_tls_version = azurerm_storage_account.main.min_tls_version
    sql_min_tls_version     = azurerm_mssql_server.main.minimum_tls_version
    redis_min_tls_version   = azurerm_redis_cache.main.minimum_tls_version
    key_vault_rbac_enabled  = azurerm_key_vault.main.enable_rbac_authorization
    managed_identities      = "System-assigned identities enabled for Function App and Web App"
  }
}