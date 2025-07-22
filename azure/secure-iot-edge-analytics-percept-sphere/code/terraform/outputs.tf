# =============================================================================
# Outputs for Azure IoT Edge Analytics with Percept and Sphere
# =============================================================================
# This file defines all output values from the IoT Edge Analytics Terraform 
# deployment, providing important information for verification, integration,
# and operational management.

# =============================================================================
# Resource Group Outputs
# =============================================================================

output "resource_group_name" {
  description = "Name of the resource group containing all IoT Edge Analytics resources"
  value       = azurerm_resource_group.iot_edge_analytics.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.iot_edge_analytics.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.iot_edge_analytics.location
}

# =============================================================================
# IoT Hub Outputs
# =============================================================================

output "iot_hub_name" {
  description = "Name of the IoT Hub"
  value       = azurerm_iothub.iot_hub.name
}

output "iot_hub_id" {
  description = "ID of the IoT Hub"
  value       = azurerm_iothub.iot_hub.id
}

output "iot_hub_hostname" {
  description = "Hostname of the IoT Hub"
  value       = azurerm_iothub.iot_hub.hostname
}

output "iot_hub_event_hub_events_endpoint" {
  description = "Event Hub-compatible endpoint for IoT Hub events"
  value       = azurerm_iothub.iot_hub.event_hub_events_endpoint
}

output "iot_hub_event_hub_events_path" {
  description = "Event Hub-compatible path for IoT Hub events"
  value       = azurerm_iothub.iot_hub.event_hub_events_path
}

output "iot_hub_event_hub_operations_endpoint" {
  description = "Event Hub-compatible endpoint for IoT Hub operations monitoring"
  value       = azurerm_iothub.iot_hub.event_hub_operations_endpoint
}

output "iot_hub_event_hub_operations_path" {
  description = "Event Hub-compatible path for IoT Hub operations monitoring"
  value       = azurerm_iothub.iot_hub.event_hub_operations_path
}

output "iot_hub_shared_access_policy_name" {
  description = "Name of the IoT Hub shared access policy"
  value       = azurerm_iothub.iot_hub.shared_access_policy[0].key_name
}

output "iot_hub_connection_string" {
  description = "Connection string for the IoT Hub (sensitive)"
  value       = azurerm_iothub.iot_hub.shared_access_policy[0].connection_string
  sensitive   = true
}

# =============================================================================
# Storage Account Outputs
# =============================================================================

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.iot_storage.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.iot_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint URL of the storage account"
  value       = azurerm_storage_account.iot_storage.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.iot_storage.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account (sensitive)"
  value       = azurerm_storage_account.iot_storage.primary_access_key
  sensitive   = true
}

output "processed_telemetry_container_name" {
  description = "Name of the processed telemetry storage container"
  value       = azurerm_storage_container.processed_telemetry.name
}

output "raw_telemetry_container_name" {
  description = "Name of the raw telemetry storage container"
  value       = azurerm_storage_container.raw_telemetry.name
}

output "data_lake_gen2_endpoint" {
  description = "Data Lake Gen2 endpoint URL"
  value       = azurerm_storage_account.iot_storage.primary_dfs_endpoint
}

# =============================================================================
# Stream Analytics Outputs
# =============================================================================

output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.iot_stream_analytics.name
}

output "stream_analytics_job_id" {
  description = "ID of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.iot_stream_analytics.id
}

output "stream_analytics_job_streaming_units" {
  description = "Number of streaming units allocated to the Stream Analytics job"
  value       = azurerm_stream_analytics_job.iot_stream_analytics.streaming_units
}

output "stream_analytics_job_compatibility_level" {
  description = "Compatibility level of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.iot_stream_analytics.compatibility_level
}

output "stream_analytics_consumer_group_name" {
  description = "Name of the consumer group for Stream Analytics"
  value       = azurerm_iothub_consumer_group.stream_analytics.name
}

# =============================================================================
# Log Analytics and Monitoring Outputs
# =============================================================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.iot_logs.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.iot_logs.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.iot_logs.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace (sensitive)"
  value       = azurerm_log_analytics_workspace.iot_logs.primary_shared_key
  sensitive   = true
}

output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = azurerm_application_insights.iot_insights.name
}

output "application_insights_id" {
  description = "ID of the Application Insights component"
  value       = azurerm_application_insights.iot_insights.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = azurerm_application_insights.iot_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = azurerm_application_insights.iot_insights.connection_string
  sensitive   = true
}

# =============================================================================
# Key Vault Outputs
# =============================================================================

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.iot_key_vault.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.iot_key_vault.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.iot_key_vault.vault_uri
}

# =============================================================================
# Alerting and Monitoring Outputs
# =============================================================================

output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = azurerm_monitor_action_group.iot_alerts.name
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = azurerm_monitor_action_group.iot_alerts.id
}

output "stream_analytics_error_alert_id" {
  description = "ID of the Stream Analytics error alert"
  value       = azurerm_monitor_metric_alert.stream_analytics_errors.id
}

output "iot_hub_connectivity_alert_id" {
  description = "ID of the IoT Hub connectivity alert"
  value       = azurerm_monitor_metric_alert.iot_hub_connectivity.id
}

output "iot_hub_throttling_alert_id" {
  description = "ID of the IoT Hub throttling alert"
  value       = azurerm_monitor_metric_alert.iot_hub_throttling.id
}

# =============================================================================
# Device Configuration Outputs
# =============================================================================

output "percept_device_id" {
  description = "Device ID for Azure Percept device"
  value       = var.percept_device_id
}

output "sphere_device_id" {
  description = "Device ID for Azure Sphere device"
  value       = var.sphere_device_id
}

# =============================================================================
# Networking and Security Outputs
# =============================================================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# =============================================================================
# Configuration Outputs for Device Setup
# =============================================================================

output "device_connection_configuration" {
  description = "Configuration information for device setup"
  value = {
    iot_hub_name     = azurerm_iothub.iot_hub.name
    iot_hub_hostname = azurerm_iothub.iot_hub.hostname
    percept_device_id = var.percept_device_id
    sphere_device_id  = var.sphere_device_id
    storage_account_name = azurerm_storage_account.iot_storage.name
    processed_telemetry_container = azurerm_storage_container.processed_telemetry.name
    raw_telemetry_container = azurerm_storage_container.raw_telemetry.name
    stream_analytics_job_name = azurerm_stream_analytics_job.iot_stream_analytics.name
    consumer_group_name = azurerm_iothub_consumer_group.stream_analytics.name
  }
}

# =============================================================================
# Monitoring and Diagnostics Outputs
# =============================================================================

output "monitoring_configuration" {
  description = "Monitoring and diagnostics configuration"
  value = {
    log_analytics_workspace_name = azurerm_log_analytics_workspace.iot_logs.name
    log_analytics_workspace_id   = azurerm_log_analytics_workspace.iot_logs.workspace_id
    application_insights_name     = azurerm_application_insights.iot_insights.name
    action_group_name            = azurerm_monitor_action_group.iot_alerts.name
    key_vault_name               = azurerm_key_vault.iot_key_vault.name
    key_vault_uri                = azurerm_key_vault.iot_key_vault.vault_uri
  }
}

# =============================================================================
# Cost Management Outputs
# =============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the IoT Edge Analytics solution"
  value = {
    currency = "USD"
    breakdown = {
      iot_hub_s1_1_unit = "25.00"
      stream_analytics_1_su = "80.00"
      storage_account_lrs = "20.00"
      log_analytics_workspace = "15.00"
      application_insights = "10.00"
      key_vault = "5.00"
      monitoring_alerts = "5.00"
      total_estimated = "160.00"
    }
    note = "Costs are estimates based on standard pricing and may vary based on actual usage, region, and current pricing. Monitor actual costs using Azure Cost Management."
  }
}

# =============================================================================
# Deployment Information
# =============================================================================

output "deployment_information" {
  description = "Important deployment and setup information"
  value = {
    deployment_timestamp = timestamp()
    terraform_version = ">=1.0"
    azurerm_provider_version = ">=3.0"
    resource_group_name = azurerm_resource_group.iot_edge_analytics.name
    location = azurerm_resource_group.iot_edge_analytics.location
    environment = var.environment
    next_steps = [
      "1. Configure Azure Percept device with the provided IoT Hub connection details",
      "2. Set up Azure Sphere device with X.509 certificates",
      "3. Deploy edge modules to Azure Percept device",
      "4. Start the Stream Analytics job to begin real-time processing",
      "5. Monitor telemetry flow in Azure portal",
      "6. Set up additional device twins and desired properties as needed",
      "7. Configure custom alerting rules based on your specific requirements"
    ]
  }
}

# =============================================================================
# Connection Strings for Device Configuration (Sensitive)
# =============================================================================

output "device_connection_strings" {
  description = "Connection strings and keys for device configuration (sensitive)"
  value = {
    iot_hub_connection_string = azurerm_iothub.iot_hub.shared_access_policy[0].connection_string
    storage_connection_string = azurerm_storage_account.iot_storage.primary_connection_string
    log_analytics_workspace_key = azurerm_log_analytics_workspace.iot_logs.primary_shared_key
    application_insights_instrumentation_key = azurerm_application_insights.iot_insights.instrumentation_key
  }
  sensitive = true
}

# =============================================================================
# Validation Outputs
# =============================================================================

output "deployment_validation" {
  description = "Validation information for the deployment"
  value = {
    iot_hub_created = azurerm_iothub.iot_hub.name != null
    storage_account_created = azurerm_storage_account.iot_storage.name != null
    stream_analytics_created = azurerm_stream_analytics_job.iot_stream_analytics.name != null
    containers_created = length([
      azurerm_storage_container.processed_telemetry.name,
      azurerm_storage_container.raw_telemetry.name
    ]) == 2
    monitoring_configured = azurerm_log_analytics_workspace.iot_logs.name != null
    alerts_configured = azurerm_monitor_action_group.iot_alerts.name != null
    key_vault_created = azurerm_key_vault.iot_key_vault.name != null
    diagnostic_settings_configured = length([
      azurerm_monitor_diagnostic_setting.iot_hub_diagnostics.name,
      azurerm_monitor_diagnostic_setting.stream_analytics_diagnostics.name,
      azurerm_monitor_diagnostic_setting.storage_diagnostics.name
    ]) == 3
    deployment_status = "SUCCESS"
  }
}