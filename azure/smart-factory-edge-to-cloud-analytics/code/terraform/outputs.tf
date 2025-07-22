# Output Values for Azure IoT Operations Manufacturing Analytics Solution
# This file defines all output values that provide important information
# about the deployed resources for integration and monitoring purposes

# ==============================================================================
# RESOURCE GROUP AND LOCATION OUTPUTS
# ==============================================================================

output "resource_group_name" {
  description = "Name of the Azure resource group containing all manufacturing analytics resources"
  value       = azurerm_resource_group.manufacturing_analytics.name
}

output "resource_group_id" {
  description = "Resource ID of the Azure resource group"
  value       = azurerm_resource_group.manufacturing_analytics.id
}

output "location" {
  description = "Azure region where all resources are deployed"
  value       = azurerm_resource_group.manufacturing_analytics.location
}

# ==============================================================================
# EVENT HUBS OUTPUTS FOR TELEMETRY INGESTION
# ==============================================================================

output "event_hubs_namespace_name" {
  description = "Name of the Event Hubs namespace for manufacturing telemetry"
  value       = azurerm_eventhub_namespace.manufacturing_telemetry.name
}

output "event_hubs_namespace_id" {
  description = "Resource ID of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.manufacturing_telemetry.id
}

output "event_hubs_namespace_fqdn" {
  description = "Fully qualified domain name of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.manufacturing_telemetry.default_primary_connection_string_alias
}

output "telemetry_event_hub_name" {
  description = "Name of the main telemetry Event Hub for manufacturing data"
  value       = azurerm_eventhub.manufacturing_telemetry_hub.name
}

output "telemetry_event_hub_id" {
  description = "Resource ID of the telemetry Event Hub"
  value       = azurerm_eventhub.manufacturing_telemetry_hub.id
}

output "alerts_event_hub_name" {
  description = "Name of the alerts Event Hub for processed alerts"
  value       = azurerm_eventhub.manufacturing_alerts_hub.name
}

output "alerts_event_hub_id" {
  description = "Resource ID of the alerts Event Hub"
  value       = azurerm_eventhub.manufacturing_alerts_hub.id
}

# ==============================================================================
# EVENT HUBS CONNECTION STRINGS AND ACCESS KEYS
# ==============================================================================

output "event_hubs_connection_string" {
  description = "Primary connection string for Event Hubs namespace (sensitive)"
  value       = azurerm_eventhub_namespace.manufacturing_telemetry.default_primary_connection_string
  sensitive   = true
}

output "iot_operations_connection_string" {
  description = "Connection string for IoT Operations access to Event Hubs (sensitive)"
  value       = azurerm_eventhub_authorization_rule.iot_operations_access.primary_connection_string
  sensitive   = true
}

output "iot_operations_access_key" {
  description = "Primary access key for IoT Operations Event Hub access (sensitive)"
  value       = azurerm_eventhub_authorization_rule.iot_operations_access.primary_key
  sensitive   = true
}

# ==============================================================================
# STREAM ANALYTICS OUTPUTS
# ==============================================================================

output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job for manufacturing analytics"
  value       = azurerm_stream_analytics_job.manufacturing_analytics.name
}

output "stream_analytics_job_id" {
  description = "Resource ID of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.manufacturing_analytics.id
}

output "stream_analytics_job_state" {
  description = "Current state of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.manufacturing_analytics.job_state
}

output "stream_analytics_streaming_units" {
  description = "Number of streaming units configured for the Stream Analytics job"
  value       = azurerm_stream_analytics_job.manufacturing_analytics.streaming_units
}

# ==============================================================================
# STORAGE ACCOUNT OUTPUTS
# ==============================================================================

output "storage_account_name" {
  description = "Name of the storage account for telemetry archive and analytics data"
  value       = azurerm_storage_account.manufacturing_data.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.manufacturing_data.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint URL for the storage account"
  value       = azurerm_storage_account.manufacturing_data.primary_blob_endpoint
}

output "telemetry_archive_container_name" {
  description = "Name of the container for telemetry archive data"
  value       = azurerm_storage_container.telemetry_archive.name
}

output "analytics_data_container_name" {
  description = "Name of the container for processed analytics data"
  value       = azurerm_storage_container.analytics_data.name
}

output "storage_account_access_key" {
  description = "Primary access key for the storage account (sensitive)"
  value       = azurerm_storage_account.manufacturing_data.primary_access_key
  sensitive   = true
}

# ==============================================================================
# MONITORING AND LOGGING OUTPUTS
# ==============================================================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for monitoring"
  value       = azurerm_log_analytics_workspace.manufacturing_monitoring.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.manufacturing_monitoring.id
}

output "log_analytics_workspace_resource_id" {
  description = "Full resource ID of the Log Analytics workspace for diagnostic settings"
  value       = azurerm_log_analytics_workspace.manufacturing_monitoring.id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.manufacturing_insights.name
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance"
  value       = azurerm_application_insights.manufacturing_insights.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = azurerm_application_insights.manufacturing_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = azurerm_application_insights.manufacturing_insights.connection_string
  sensitive   = true
}

# ==============================================================================
# ALERTING AND NOTIFICATION OUTPUTS
# ==============================================================================

output "action_group_name" {
  description = "Name of the action group for manufacturing maintenance alerts"
  value       = var.enable_alerts ? azurerm_monitor_action_group.manufacturing_maintenance[0].name : null
}

output "action_group_id" {
  description = "Resource ID of the action group"
  value       = var.enable_alerts ? azurerm_monitor_action_group.manufacturing_maintenance[0].id : null
}

output "critical_equipment_alert_name" {
  description = "Name of the critical equipment alert rule"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.critical_equipment_alert[0].name : null
}

output "stream_analytics_failure_alert_name" {
  description = "Name of the Stream Analytics failure alert rule"
  value       = var.enable_alerts ? azurerm_monitor_activity_log_alert.stream_analytics_failure[0].name : null
}

# ==============================================================================
# IOT OPERATIONS OUTPUTS (WHEN ENABLED)
# ==============================================================================

output "iot_operations_config_enabled" {
  description = "Whether IoT Operations configuration is enabled"
  value       = var.enable_iot_operations && var.arc_cluster_name != null
}

output "iot_operations_config_file_path" {
  description = "Path to the IoT Operations configuration file (when enabled)"
  value       = var.enable_iot_operations && var.arc_cluster_name != null ? "${path.module}/iot-operations-config.yaml" : null
}

output "iot_operations_instance_name" {
  description = "Planned name for the Azure IoT Operations instance (when enabled)"
  value       = var.enable_iot_operations && var.arc_cluster_name != null ? "iot-ops-${local.resource_suffix}" : null
}

output "arc_cluster_resource_id" {
  description = "Resource ID of the Azure Arc-enabled Kubernetes cluster (when specified)"
  value       = var.enable_iot_operations && var.arc_cluster_name != null ? "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.arc_cluster_resource_group}/providers/Microsoft.Kubernetes/connectedClusters/${var.arc_cluster_name}" : null
}

# ==============================================================================
# MANAGED IDENTITY OUTPUTS
# ==============================================================================

output "event_hubs_managed_identity_principal_id" {
  description = "Principal ID of the Event Hubs namespace managed identity"
  value       = var.enable_managed_identity ? azurerm_eventhub_namespace.manufacturing_telemetry.identity[0].principal_id : null
}

output "stream_analytics_managed_identity_principal_id" {
  description = "Principal ID of the Stream Analytics job managed identity"
  value       = var.enable_managed_identity ? azurerm_stream_analytics_job.manufacturing_analytics.identity[0].principal_id : null
}

output "storage_account_managed_identity_principal_id" {
  description = "Principal ID of the storage account managed identity"
  value       = var.enable_managed_identity ? azurerm_storage_account.manufacturing_data.identity[0].principal_id : null
}

# ==============================================================================
# NETWORK AND SECURITY OUTPUTS
# ==============================================================================

output "allowed_ip_ranges" {
  description = "List of IP address ranges allowed to access Event Hubs"
  value       = var.allowed_ip_ranges
}

output "private_endpoints_enabled" {
  description = "Whether private endpoints are enabled for secure access"
  value       = var.enable_private_endpoints
}

# ==============================================================================
# COST OPTIMIZATION AND CONFIGURATION OUTPUTS
# ==============================================================================

output "event_hubs_throughput_units" {
  description = "Current throughput units configured for Event Hubs namespace"
  value       = azurerm_eventhub_namespace.manufacturing_telemetry.capacity
}

output "event_hubs_auto_inflate_enabled" {
  description = "Whether auto-inflate is enabled for Event Hubs namespace"
  value       = azurerm_eventhub_namespace.manufacturing_telemetry.auto_inflate_enabled
}

output "event_hubs_maximum_throughput_units" {
  description = "Maximum throughput units when auto-inflate is enabled"
  value       = azurerm_eventhub_namespace.manufacturing_telemetry.maximum_throughput_units
}

output "telemetry_partition_count" {
  description = "Number of partitions configured for the telemetry Event Hub"
  value       = azurerm_eventhub.manufacturing_telemetry_hub.partition_count
}

output "telemetry_message_retention_days" {
  description = "Message retention period in days for telemetry Event Hub"
  value       = azurerm_eventhub.manufacturing_telemetry_hub.message_retention
}

# ==============================================================================
# DEPLOYMENT INFORMATION OUTPUTS
# ==============================================================================

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_version" {
  description = "Version of Terraform used for deployment"
  value       = "~> 1.5.0"
}

output "solution_tags" {
  description = "Common tags applied to all resources in the solution"
  value       = local.common_tags
}

output "resource_suffix" {
  description = "Unique suffix applied to resource names to avoid conflicts"
  value       = local.resource_suffix
}

# ==============================================================================
# INTEGRATION ENDPOINTS AND CONFIGURATION
# ==============================================================================

output "telemetry_ingestion_endpoint" {
  description = "Endpoint URL for telemetry data ingestion via Event Hubs"
  value       = "sb://${azurerm_eventhub_namespace.manufacturing_telemetry.name}.servicebus.windows.net/"
}

output "monitoring_dashboard_url" {
  description = "URL to access Azure Portal monitoring dashboard"
  value       = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.manufacturing_monitoring.id}/overview"
}

output "stream_analytics_portal_url" {
  description = "URL to access Stream Analytics job in Azure Portal"
  value       = "https://portal.azure.com/#@/resource${azurerm_stream_analytics_job.manufacturing_analytics.id}/overview"
}

# ==============================================================================
# QUICK START CONFIGURATION VALUES
# ==============================================================================

output "quick_start_config" {
  description = "Configuration values for quick start deployment verification"
  value = {
    event_hubs_namespace     = azurerm_eventhub_namespace.manufacturing_telemetry.name
    telemetry_hub           = azurerm_eventhub.manufacturing_telemetry_hub.name
    alerts_hub              = azurerm_eventhub.manufacturing_alerts_hub.name
    stream_analytics_job    = azurerm_stream_analytics_job.manufacturing_analytics.name
    storage_account         = azurerm_storage_account.manufacturing_data.name
    log_analytics_workspace = azurerm_log_analytics_workspace.manufacturing_monitoring.name
    resource_group          = azurerm_resource_group.manufacturing_analytics.name
    location               = azurerm_resource_group.manufacturing_analytics.location
  }
}