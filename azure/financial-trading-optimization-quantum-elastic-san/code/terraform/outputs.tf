# Output values for Azure Quantum Financial Trading Infrastructure
# These outputs provide important resource information for integration and validation

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all quantum trading resources"
  value       = azurerm_resource_group.quantum_trading.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.quantum_trading.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.quantum_trading.location
}

# Azure Quantum Workspace Information
output "quantum_workspace_name" {
  description = "Name of the Azure Quantum workspace for portfolio optimization"
  value       = azurerm_quantum_workspace.quantum_trading.name
}

output "quantum_workspace_id" {
  description = "ID of the Azure Quantum workspace"
  value       = azurerm_quantum_workspace.quantum_trading.id
}

output "quantum_workspace_endpoint" {
  description = "Endpoint URL for the Azure Quantum workspace"
  value       = "https://quantum.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.quantum_trading.name}/providers/Microsoft.Quantum/Workspaces/${azurerm_quantum_workspace.quantum_trading.name}"
}

# Azure Elastic SAN Information
output "elastic_san_name" {
  description = "Name of the Azure Elastic SAN for high-performance storage"
  value       = azurerm_elastic_san.quantum_trading.name
}

output "elastic_san_id" {
  description = "ID of the Azure Elastic SAN"
  value       = azurerm_elastic_san.quantum_trading.id
}

output "elastic_san_base_size_tib" {
  description = "Base size of the Elastic SAN in TiB"
  value       = azurerm_elastic_san.quantum_trading.base_size_in_tib
}

output "elastic_san_total_capacity_tib" {
  description = "Total capacity of the Elastic SAN (base + extended) in TiB"
  value       = azurerm_elastic_san.quantum_trading.base_size_in_tib + azurerm_elastic_san.quantum_trading.extended_capacity_size_in_tib
}

output "market_data_volume_group_id" {
  description = "ID of the market data volume group"
  value       = azurerm_elastic_san_volume_group.market_data.id
}

output "realtime_data_volume_id" {
  description = "ID of the real-time market data volume"
  value       = azurerm_elastic_san_volume.realtime_data.id
}

output "realtime_data_volume_size_gib" {
  description = "Size of the real-time data volume in GiB"
  value       = azurerm_elastic_san_volume.realtime_data.size_in_gib
}

# Machine Learning Workspace Information
output "ml_workspace_name" {
  description = "Name of the Azure ML workspace for hybrid algorithm orchestration"
  value       = azurerm_machine_learning_workspace.quantum_trading.name
}

output "ml_workspace_id" {
  description = "ID of the Azure ML workspace"
  value       = azurerm_machine_learning_workspace.quantum_trading.id
}

output "ml_workspace_discovery_url" {
  description = "Discovery URL for the ML workspace"
  value       = azurerm_machine_learning_workspace.quantum_trading.discovery_url
}

output "ml_compute_cluster_name" {
  description = "Name of the ML compute cluster for quantum-classical hybrid algorithms"
  value       = azurerm_machine_learning_compute_cluster.quantum_compute.name
}

output "ml_compute_cluster_configuration" {
  description = "Configuration details of the ML compute cluster"
  value = {
    vm_size    = azurerm_machine_learning_compute_cluster.quantum_compute.vm_size
    min_nodes  = azurerm_machine_learning_compute_cluster.quantum_compute.scale_settings[0].min_node_count
    max_nodes  = azurerm_machine_learning_compute_cluster.quantum_compute.scale_settings[0].max_node_count
    vm_priority = azurerm_machine_learning_compute_cluster.quantum_compute.vm_priority
  }
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for quantum workspace and data"
  value       = azurerm_storage_account.quantum_trading.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.quantum_trading.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.quantum_trading.primary_blob_endpoint
}

output "market_data_archive_container" {
  description = "Name of the market data archive container"
  value       = azurerm_storage_container.market_data_archive.name
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for secure credential management"
  value       = azurerm_key_vault.quantum_trading.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.quantum_trading.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.quantum_trading.vault_uri
}

# Real-time Data Processing Information
output "event_hub_namespace_name" {
  description = "Name of the Event Hub namespace for market data streaming"
  value       = azurerm_eventhub_namespace.market_data.name
}

output "event_hub_namespace_connection_string" {
  description = "Primary connection string for Event Hub namespace"
  value       = azurerm_eventhub_namespace.market_data.default_primary_connection_string
  sensitive   = true
}

output "market_data_event_hub_name" {
  description = "Name of the market data Event Hub"
  value       = azurerm_eventhub.market_data_stream.name
}

output "data_factory_name" {
  description = "Name of the Data Factory for market data ingestion"
  value       = azurerm_data_factory.market_data.name
}

output "data_factory_id" {
  description = "ID of the Data Factory"
  value       = azurerm_data_factory.market_data.id
}

output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job for real-time processing"
  value       = azurerm_stream_analytics_job.quantum_trading.name
}

output "stream_analytics_streaming_units" {
  description = "Number of streaming units allocated to Stream Analytics job"
  value       = azurerm_stream_analytics_job.quantum_trading.streaming_units
}

# Monitoring and Logging Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for monitoring"
  value       = azurerm_log_analytics_workspace.quantum_trading.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.quantum_trading.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) for Log Analytics"
  value       = azurerm_log_analytics_workspace.quantum_trading.workspace_id
}

output "application_insights_name" {
  description = "Name of Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.quantum_trading[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.quantum_trading[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.quantum_trading[0].connection_string : null
  sensitive   = true
}

# Network Information
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.quantum_trading.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.quantum_trading.id
}

output "private_endpoints_subnet_id" {
  description = "ID of the subnet for private endpoints"
  value       = azurerm_subnet.private_endpoints.id
}

output "network_security_group_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.quantum_trading.id
}

# Security and Access Information
output "private_endpoints_enabled" {
  description = "Whether private endpoints are enabled for enhanced security"
  value       = var.enable_private_endpoints
}

output "storage_private_endpoint_id" {
  description = "ID of the storage account private endpoint (if enabled)"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.storage[0].id : null
}

output "key_vault_private_endpoint_id" {
  description = "ID of the Key Vault private endpoint (if enabled)"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.key_vault[0].id : null
}

# Service Principal and Identity Information
output "ml_workspace_principal_id" {
  description = "Principal ID of the ML workspace managed identity"
  value       = azurerm_machine_learning_workspace.quantum_trading.identity[0].principal_id
}

output "data_factory_principal_id" {
  description = "Principal ID of the Data Factory managed identity"
  value       = azurerm_data_factory.market_data.identity[0].principal_id
}

# Cost Management Information
output "auto_shutdown_enabled" {
  description = "Whether automatic shutdown is enabled for cost optimization"
  value       = var.enable_auto_shutdown
}

output "auto_shutdown_time" {
  description = "Time when compute resources automatically shut down"
  value       = var.enable_auto_shutdown ? var.auto_shutdown_time : null
}

output "geo_redundancy_enabled" {
  description = "Whether geo-redundant storage is enabled"
  value       = var.enable_geo_redundancy
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Integration Endpoints and Configuration
output "quantum_algorithm_endpoints" {
  description = "Important endpoints for quantum algorithm integration"
  value = {
    quantum_workspace_endpoint = "https://quantum.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.quantum_trading.name}/providers/Microsoft.Quantum/Workspaces/${azurerm_quantum_workspace.quantum_trading.name}"
    ml_workspace_endpoint     = azurerm_machine_learning_workspace.quantum_trading.discovery_url
    storage_blob_endpoint     = azurerm_storage_account.quantum_trading.primary_blob_endpoint
    key_vault_endpoint        = azurerm_key_vault.quantum_trading.vault_uri
  }
}

output "monitoring_endpoints" {
  description = "Endpoints for monitoring and observability"
  value = {
    log_analytics_portal_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.quantum_trading.id}/overview"
    application_insights_url = var.enable_application_insights ? "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.quantum_trading[0].id}/overview" : null
  }
}

# Performance Configuration Summary
output "performance_configuration" {
  description = "Summary of performance-related configurations"
  value = {
    elastic_san_total_capacity_tib = azurerm_elastic_san.quantum_trading.base_size_in_tib + azurerm_elastic_san.quantum_trading.extended_capacity_size_in_tib
    elastic_san_sku               = "Premium_LRS"
    event_hub_throughput_units    = azurerm_eventhub_namespace.market_data.capacity
    stream_analytics_units        = azurerm_stream_analytics_job.quantum_trading.streaming_units
    ml_compute_max_nodes          = azurerm_machine_learning_compute_cluster.quantum_compute.scale_settings[0].max_node_count
    storage_replication_type      = azurerm_storage_account.quantum_trading.account_replication_type
  }
}

# Connection Strings and Access Keys (Sensitive)
output "quantum_workspace_access_info" {
  description = "Access information for the Quantum workspace"
  value = {
    resource_id = azurerm_quantum_workspace.quantum_trading.id
    location    = azurerm_quantum_workspace.quantum_trading.location
  }
  sensitive = false
}

# Trading Algorithm Configuration
output "trading_algorithm_config" {
  description = "Configuration summary for trading algorithm deployment"
  value = {
    risk_tolerance      = var.risk_tolerance
    portfolio_size_limit = var.portfolio_size_limit
    quantum_providers   = var.quantum_providers
    backup_retention_days = var.backup_retention_days
    log_retention_days  = var.log_retention_days
  }
}