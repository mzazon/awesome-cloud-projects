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
  description = "Resource group ID"
  value       = azurerm_resource_group.main.id
}

# Network Information
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "cassandra_subnet_id" {
  description = "ID of the Cassandra subnet"
  value       = azurerm_subnet.cassandra.id
}

output "cassandra_subnet_address_prefix" {
  description = "Address prefix of the Cassandra subnet"
  value       = azurerm_subnet.cassandra.address_prefixes[0]
}

# Cassandra Cluster Information
output "cassandra_cluster_name" {
  description = "Name of the Cassandra cluster"
  value       = azurerm_cosmosdb_cassandra_cluster.main.name
}

output "cassandra_cluster_id" {
  description = "ID of the Cassandra cluster"
  value       = azurerm_cosmosdb_cassandra_cluster.main.id
}

output "cassandra_cluster_version" {
  description = "Version of Apache Cassandra deployed"
  value       = azurerm_cosmosdb_cassandra_cluster.main.version
}

output "cassandra_seed_nodes" {
  description = "List of Cassandra seed node IP addresses"
  value       = azurerm_cosmosdb_cassandra_cluster.main.cassandra_seeds
}

# Cassandra Data Center Information
output "cassandra_datacenter_name" {
  description = "Name of the Cassandra datacenter"
  value       = azurerm_cosmosdb_cassandra_datacenter.main.name
}

output "cassandra_datacenter_id" {
  description = "ID of the Cassandra datacenter"
  value       = azurerm_cosmosdb_cassandra_datacenter.main.id
}

output "cassandra_node_count" {
  description = "Number of nodes in the Cassandra datacenter"
  value       = azurerm_cosmosdb_cassandra_datacenter.main.node_count
}

output "cassandra_node_sku" {
  description = "SKU of the Cassandra datacenter nodes"
  value       = azurerm_cosmosdb_cassandra_datacenter.main.sku_name
}

# Grafana Information
output "grafana_name" {
  description = "Name of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.main.name
}

output "grafana_id" {
  description = "ID of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.main.id
}

output "grafana_endpoint" {
  description = "Public endpoint URL for Azure Managed Grafana"
  value       = azurerm_dashboard_grafana.main.endpoint
}

output "grafana_grafana_version" {
  description = "Version of Grafana deployed"
  value       = azurerm_dashboard_grafana.main.grafana_version
}

output "grafana_sku" {
  description = "SKU of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.main.sku
}

output "grafana_outbound_ips" {
  description = "List of outbound IP addresses for Grafana"
  value       = azurerm_dashboard_grafana.main.outbound_ip
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (GUID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Alert Configuration
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = var.alert_enabled ? azurerm_monitor_action_group.main[0].name : null
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = var.alert_enabled ? azurerm_monitor_action_group.main[0].id : null
}

output "high_cpu_alert_name" {
  description = "Name of the high CPU usage alert"
  value       = var.alert_enabled ? azurerm_monitor_metric_alert.high_cpu[0].name : null
}

output "high_memory_alert_name" {
  description = "Name of the high memory usage alert"
  value       = var.alert_enabled ? azurerm_monitor_metric_alert.high_memory[0].name : null
}

output "low_disk_space_alert_name" {
  description = "Name of the low disk space alert"
  value       = var.alert_enabled ? azurerm_monitor_metric_alert.low_disk_space[0].name : null
}

# Connection Information
output "cassandra_connection_info" {
  description = "Connection information for Cassandra cluster"
  value = {
    cluster_name = azurerm_cosmosdb_cassandra_cluster.main.name
    seed_nodes   = azurerm_cosmosdb_cassandra_cluster.main.cassandra_seeds
    port         = 9042
    ssl_enabled  = true
    version      = azurerm_cosmosdb_cassandra_cluster.main.version
  }
}

# Monitoring URLs
output "monitoring_urls" {
  description = "URLs for accessing monitoring services"
  value = {
    grafana_url                = azurerm_dashboard_grafana.main.endpoint
    azure_portal_cassandra_url = "https://portal.azure.com/#@/resource${azurerm_cosmosdb_cassandra_cluster.main.id}/overview"
    azure_portal_grafana_url   = "https://portal.azure.com/#@/resource${azurerm_dashboard_grafana.main.id}/overview"
    log_analytics_url          = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/logs"
  }
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group        = azurerm_resource_group.main.name
    location             = azurerm_resource_group.main.location
    cassandra_cluster    = azurerm_cosmosdb_cassandra_cluster.main.name
    cassandra_nodes      = azurerm_cosmosdb_cassandra_datacenter.main.node_count
    grafana_instance     = azurerm_dashboard_grafana.main.name
    monitoring_workspace = azurerm_log_analytics_workspace.main.name
    alerts_enabled       = var.alert_enabled
    estimated_monthly_cost = "USD $300-500 (varies by usage and region)"
  }
}

# Tags Applied
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}