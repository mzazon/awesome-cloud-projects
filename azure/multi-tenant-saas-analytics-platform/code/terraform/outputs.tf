# Output values for Azure multi-tenant SaaS performance and cost analytics solution
# These outputs provide important resource information for integration and verification

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.analytics.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.analytics.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.analytics.location
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.analytics.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.analytics.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (Customer ID) for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.analytics.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.analytics.primary_shared_key
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.analytics.name
}

output "application_insights_id" {
  description = "ID of the Application Insights resource"
  value       = azurerm_application_insights.analytics.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.analytics.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (recommended for modern SDKs)"
  value       = azurerm_application_insights.analytics.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.analytics.app_id
}

# Azure Data Explorer Information
output "data_explorer_cluster_name" {
  description = "Name of the Azure Data Explorer cluster"
  value       = azurerm_kusto_cluster.analytics.name
}

output "data_explorer_cluster_id" {
  description = "ID of the Azure Data Explorer cluster"
  value       = azurerm_kusto_cluster.analytics.id
}

output "data_explorer_cluster_uri" {
  description = "URI for connecting to the Azure Data Explorer cluster"
  value       = azurerm_kusto_cluster.analytics.uri
}

output "data_explorer_data_ingestion_uri" {
  description = "Data ingestion URI for the Azure Data Explorer cluster"
  value       = azurerm_kusto_cluster.analytics.data_ingestion_uri
}

output "data_explorer_database_name" {
  description = "Name of the Azure Data Explorer database"
  value       = azurerm_kusto_database.analytics.name
}

output "data_explorer_database_id" {
  description = "ID of the Azure Data Explorer database"
  value       = azurerm_kusto_database.analytics.id
}

output "data_explorer_cluster_principal_id" {
  description = "Principal ID of the Data Explorer cluster managed identity"
  value       = azurerm_kusto_cluster.analytics.identity[0].principal_id
}

# Event Hub Information
output "eventhub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.analytics.name
}

output "eventhub_name" {
  description = "Name of the Event Hub for telemetry streaming"
  value       = azurerm_eventhub.analytics.name
}

output "eventhub_connection_string" {
  description = "Connection string for the Event Hub namespace"
  value       = azurerm_eventhub_namespace.analytics.default_primary_connection_string
  sensitive   = true
}

output "eventhub_consumer_group_name" {
  description = "Name of the Event Hub consumer group for Data Explorer"
  value       = azurerm_eventhub_consumer_group.analytics.name
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for analytics data"
  value       = azurerm_storage_account.analytics.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.analytics.id
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.analytics.primary_access_key
  sensitive   = true
}

output "storage_container_name" {
  description = "Name of the storage container for telemetry capture"
  value       = azurerm_storage_container.analytics.name
}

# Cost Management Information
output "budget_name" {
  description = "Name of the consumption budget"
  value       = azurerm_consumption_budget_resource_group.analytics.name
}

output "budget_id" {
  description = "ID of the consumption budget"
  value       = azurerm_consumption_budget_resource_group.analytics.id
}

output "action_group_name" {
  description = "Name of the action group for cost alerts"
  value       = azurerm_monitor_action_group.cost_alerts.name
}

output "action_group_id" {
  description = "ID of the action group for cost alerts"
  value       = azurerm_monitor_action_group.cost_alerts.id
}

# Configuration Values for Application Integration
output "tenant_telemetry_configuration" {
  description = "Configuration object for application telemetry setup"
  value = {
    instrumentation_key = azurerm_application_insights.analytics.instrumentation_key
    connection_string   = azurerm_application_insights.analytics.connection_string
    workspace_id        = azurerm_log_analytics_workspace.analytics.workspace_id
    custom_properties = {
      TenantId      = "{{tenant-id}}"
      CostCenter    = var.cost_center
      Environment   = var.environment
      Solution      = var.solution_name
    }
    sampling_percentage = var.application_insights_sampling_percentage
  }
  sensitive = true
}

# Analytics Query Endpoints
output "kusto_query_endpoints" {
  description = "Kusto query endpoints and connection information"
  value = {
    cluster_uri           = azurerm_kusto_cluster.analytics.uri
    database_name         = azurerm_kusto_database.analytics.name
    tenant_metrics_table  = "TenantMetrics"
    cost_analysis_function = "TenantCostAnalysis"
    performance_function   = "TenantPerformanceAnalysis"
  }
}

# Resource tags for reference
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Network and Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    public_network_access_enabled = var.enable_public_network_access
    disk_encryption_enabled       = var.disk_encryption_enabled
    streaming_ingestion_enabled   = var.enable_streaming_ingest
    double_encryption_enabled     = var.enable_double_encryption
    storage_min_tls_version      = azurerm_storage_account.analytics.min_tls_version
  }
}

# Capacity and Scaling Information
output "scaling_configuration" {
  description = "Scaling and capacity configuration"
  value = {
    data_explorer_sku_name    = var.data_explorer_sku_name
    data_explorer_sku_tier    = var.data_explorer_sku_tier
    data_explorer_capacity    = var.data_explorer_capacity
    optimized_auto_scale      = var.optimized_auto_scale
    auto_scale_minimum        = var.auto_scale_minimum
    auto_scale_maximum        = var.auto_scale_maximum
    eventhub_partition_count  = azurerm_eventhub.analytics.partition_count
    eventhub_message_retention = azurerm_eventhub.analytics.message_retention
  }
}

# Cost Management Configuration
output "cost_management_configuration" {
  description = "Cost management and budgeting configuration"
  value = {
    budget_amount           = var.budget_amount
    budget_alert_email      = var.budget_alert_email
    budget_alert_thresholds = var.budget_alert_thresholds
    budget_time_grain       = "Monthly"
  }
}

# Integration Guidance
output "integration_guidance" {
  description = "Guidance for integrating applications with the analytics solution"
  value = {
    application_insights_sdk_setup = "Configure your application to use the connection_string output for telemetry"
    custom_telemetry_properties = "Add TenantId, CostCenter, and ResourceTier as custom properties to all telemetry"
    kusto_query_examples = "Use TenantCostAnalysis() and TenantPerformanceAnalysis() functions for analytics"
    cost_attribution = "Include TenantId in all custom dimensions for accurate cost attribution"
    recommended_metrics = "Track request count, duration, failure rate, and dependency calls per tenant"
  }
}

# Random suffix for reference
output "resource_suffix" {
  description = "Random suffix used in resource names"
  value       = random_string.suffix.result
}