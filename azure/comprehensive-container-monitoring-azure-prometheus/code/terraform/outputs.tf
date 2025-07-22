# Output values for the Azure Stateful Workload Monitoring Infrastructure
# These outputs provide essential information about the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
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

# Container Apps Environment Information
output "container_app_environment_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_app_environment_id" {
  description = "ID of the Container Apps environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_app_environment_fqdn" {
  description = "FQDN of the Container Apps environment"
  value       = azurerm_container_app_environment.main.default_domain
}

# Main Container App Information
output "container_app_name" {
  description = "Name of the main container application"
  value       = azurerm_container_app.main.name
}

output "container_app_id" {
  description = "ID of the main container application"
  value       = azurerm_container_app.main.id
}

output "container_app_fqdn" {
  description = "FQDN of the main container application"
  value       = azurerm_container_app.main.ingress[0].fqdn
}

output "container_app_latest_revision_name" {
  description = "Latest revision name of the container app"
  value       = azurerm_container_app.main.latest_revision_name
}

# Monitoring Sidecar Information (if enabled)
output "monitoring_sidecar_name" {
  description = "Name of the monitoring sidecar container app"
  value       = var.enable_monitoring_sidecar ? azurerm_container_app.monitoring_sidecar[0].name : null
}

output "monitoring_sidecar_id" {
  description = "ID of the monitoring sidecar container app"
  value       = var.enable_monitoring_sidecar ? azurerm_container_app.monitoring_sidecar[0].id : null
}

output "monitoring_sidecar_fqdn" {
  description = "FQDN of the monitoring sidecar container app"
  value       = var.enable_monitoring_sidecar ? azurerm_container_app.monitoring_sidecar[0].ingress[0].fqdn : null
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_share_name" {
  description = "Name of the storage share for PostgreSQL data"
  value       = azurerm_storage_share.postgresql_data.name
}

output "storage_share_url" {
  description = "URL of the storage share"
  value       = azurerm_storage_share.postgresql_data.url
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Azure Monitor Workspace Information
output "monitor_workspace_name" {
  description = "Name of the Azure Monitor workspace"
  value       = azurerm_monitor_workspace.main.name
}

output "monitor_workspace_id" {
  description = "ID of the Azure Monitor workspace"
  value       = azurerm_monitor_workspace.main.id
}

output "monitor_workspace_query_endpoint" {
  description = "Query endpoint of the Azure Monitor workspace"
  value       = azurerm_monitor_workspace.main.query_endpoint
}

output "monitor_workspace_default_data_collection_endpoint_id" {
  description = "Default data collection endpoint ID of the Azure Monitor workspace"
  value       = azurerm_monitor_workspace.main.default_data_collection_endpoint_id
}

# Azure Managed Grafana Information
output "grafana_instance_name" {
  description = "Name of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.main.name
}

output "grafana_instance_id" {
  description = "ID of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.main.id
}

output "grafana_endpoint" {
  description = "Endpoint URL of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.main.endpoint
}

output "grafana_grafana_version" {
  description = "Version of Grafana running in the managed instance"
  value       = azurerm_dashboard_grafana.main.grafana_version
}

# Data Collection Information
output "data_collection_endpoint_name" {
  description = "Name of the data collection endpoint"
  value       = azurerm_monitor_data_collection_endpoint.main.name
}

output "data_collection_endpoint_id" {
  description = "ID of the data collection endpoint"
  value       = azurerm_monitor_data_collection_endpoint.main.id
}

output "data_collection_rule_name" {
  description = "Name of the data collection rule"
  value       = azurerm_monitor_data_collection_rule.main.name
}

output "data_collection_rule_id" {
  description = "ID of the data collection rule"
  value       = azurerm_monitor_data_collection_rule.main.id
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of the Application Insights instance"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string of the Application Insights instance"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Alert Configuration Information (if enabled)
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = var.enable_alerts ? azurerm_monitor_action_group.main[0].name : null
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = var.enable_alerts ? azurerm_monitor_action_group.main[0].id : null
}

output "cpu_alert_name" {
  description = "Name of the CPU usage alert"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.cpu_usage[0].name : null
}

output "memory_alert_name" {
  description = "Name of the memory usage alert"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.memory_usage[0].name : null
}

output "storage_alert_name" {
  description = "Name of the storage usage alert"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.storage_usage[0].name : null
}

# Networking Information (if VNet integration is enabled)
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = var.enable_vnet_integration ? azurerm_virtual_network.main[0].name : null
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = var.enable_vnet_integration ? azurerm_virtual_network.main[0].id : null
}

output "container_subnet_name" {
  description = "Name of the container subnet"
  value       = var.enable_vnet_integration ? azurerm_subnet.container_apps[0].name : null
}

output "container_subnet_id" {
  description = "ID of the container subnet"
  value       = var.enable_vnet_integration ? azurerm_subnet.container_apps[0].id : null
}

# Database Connection Information
output "postgres_database_name" {
  description = "Name of the PostgreSQL database"
  value       = var.postgres_database_name
}

output "postgres_username" {
  description = "Username for PostgreSQL database"
  value       = var.postgres_username
}

output "postgres_connection_string" {
  description = "Connection string for PostgreSQL database (without password)"
  value       = "postgresql://${var.postgres_username}@${azurerm_container_app.main.ingress[0].fqdn}:5432/${var.postgres_database_name}"
}

# Monitoring URLs and Endpoints
output "monitoring_urls" {
  description = "URLs for accessing monitoring interfaces"
  value = {
    grafana_dashboard     = azurerm_dashboard_grafana.main.endpoint
    prometheus_endpoint   = azurerm_monitor_workspace.main.query_endpoint
    log_analytics_portal  = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.main.id}/logs"
    application_insights  = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.main.id}/overview"
  }
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group                = azurerm_resource_group.main.name
    container_app_environment     = azurerm_container_app_environment.main.name
    main_container_app           = azurerm_container_app.main.name
    monitoring_sidecar           = var.enable_monitoring_sidecar ? azurerm_container_app.monitoring_sidecar[0].name : "disabled"
    storage_account              = azurerm_storage_account.main.name
    log_analytics_workspace      = azurerm_log_analytics_workspace.main.name
    monitor_workspace            = azurerm_monitor_workspace.main.name
    grafana_instance             = azurerm_dashboard_grafana.main.name
    application_insights         = azurerm_application_insights.main.name
    vnet_integration             = var.enable_vnet_integration ? "enabled" : "disabled"
    monitoring_alerts            = var.enable_alerts ? "enabled" : "disabled"
    random_suffix                = local.suffix
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information for cost optimization"
  value = {
    container_app_scaling = {
      min_replicas = var.container_app_min_replicas
      max_replicas = var.container_app_max_replicas
      cpu_cores    = var.container_app_cpu
      memory_gb    = var.container_app_memory
    }
    storage_configuration = {
      account_tier         = var.storage_account_tier
      replication_type     = var.storage_account_replication_type
      share_quota_gb       = var.storage_share_quota
    }
    monitoring_configuration = {
      log_retention_days = var.log_analytics_retention_days
      grafana_sku       = var.grafana_sku
      alerts_enabled    = var.enable_alerts
    }
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    https_only_storage       = var.enable_https_only
    blob_public_access      = var.enable_blob_public_access
    storage_firewall        = var.enable_storage_firewall
    vnet_integration        = var.enable_vnet_integration
    grafana_public_access   = azurerm_dashboard_grafana.main.public_network_access_enabled
    tls_enabled             = !azurerm_container_app.main.ingress[0].allow_insecure_connections
  }
}