# Output values for Azure IoT Edge and Machine Learning Anomaly Detection Infrastructure
# These outputs provide essential information for connecting to and managing the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# IoT Hub Information
output "iothub_name" {
  description = "Name of the IoT Hub"
  value       = azurerm_iothub.main.name
}

output "iothub_hostname" {
  description = "Hostname of the IoT Hub"
  value       = azurerm_iothub.main.hostname
}

output "iothub_event_hub_endpoint" {
  description = "Event Hub endpoint for IoT Hub"
  value       = azurerm_iothub.main.event_hub_events_endpoint
}

output "iothub_event_hub_path" {
  description = "Event Hub path for IoT Hub"
  value       = azurerm_iothub.main.event_hub_events_path
}

# IoT Edge Device Information
output "edge_device_id" {
  description = "ID of the IoT Edge device"
  value       = azurerm_iothub_device.edge_device.device_id
}

output "edge_device_connection_string" {
  description = "Connection string for IoT Edge device (sensitive)"
  value       = azurerm_iothub_device.edge_device.primary_connection_string
  sensitive   = true
}

output "edge_device_primary_key" {
  description = "Primary key for IoT Edge device (sensitive)"
  value       = azurerm_iothub_device.edge_device.primary_key
  sensitive   = true
}

output "edge_device_secondary_key" {
  description = "Secondary key for IoT Edge device (sensitive)"
  value       = azurerm_iothub_device.edge_device.secondary_key
  sensitive   = true
}

# Machine Learning Workspace Information
output "ml_workspace_name" {
  description = "Name of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.name
}

output "ml_workspace_id" {
  description = "ID of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.id
}

output "ml_workspace_discovery_url" {
  description = "Discovery URL of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.discovery_url
}

output "ml_compute_instance_name" {
  description = "Name of the ML compute instance"
  value       = azurerm_machine_learning_compute_instance.main.name
}

output "ml_compute_cluster_name" {
  description = "Name of the ML compute cluster"
  value       = azurerm_machine_learning_compute_cluster.main.name
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string of the storage account (sensitive)"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "ml_models_container_name" {
  description = "Name of the ML models storage container"
  value       = azurerm_storage_container.ml_models.name
}

output "anomaly_data_container_name" {
  description = "Name of the anomaly data storage container"
  value       = azurerm_storage_container.anomaly_data.name
}

# Stream Analytics Information
output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.name
}

output "stream_analytics_job_id" {
  description = "ID of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.id
}

output "stream_analytics_input_name" {
  description = "Name of the Stream Analytics input"
  value       = azurerm_stream_analytics_stream_input_iothub.main.name
}

output "stream_analytics_output_name" {
  description = "Name of the Stream Analytics output"
  value       = azurerm_stream_analytics_output_eventhub.main.name
}

# Event Hub Information
output "eventhub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_name" {
  description = "Name of the Event Hub"
  value       = azurerm_eventhub.main.name
}

output "eventhub_connection_string" {
  description = "Connection string for Event Hub (sensitive)"
  value       = azurerm_eventhub_authorization_rule.main.primary_connection_string
  sensitive   = true
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

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
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

output "log_analytics_primary_key" {
  description = "Primary key for Log Analytics workspace (sensitive)"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Monitoring Information
output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = azurerm_monitor_action_group.main.name
}

output "high_anomaly_rate_alert_name" {
  description = "Name of the high anomaly rate alert"
  value       = azurerm_monitor_metric_alert.high_anomaly_rate.name
}

output "iothub_connectivity_alert_name" {
  description = "Name of the IoT Hub connectivity alert"
  value       = azurerm_monitor_metric_alert.iothub_connectivity.name
}

# Configuration Information
output "anomaly_detection_threshold" {
  description = "Configured threshold for anomaly detection"
  value       = var.anomaly_detection_threshold
}

output "anomaly_detection_window_minutes" {
  description = "Configured time window for anomaly detection (in minutes)"
  value       = var.anomaly_detection_window_minutes
}

# Generated Resource Names
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources for quick reference"
  value = {
    resource_group           = azurerm_resource_group.main.name
    iothub_name             = azurerm_iothub.main.name
    ml_workspace_name       = azurerm_machine_learning_workspace.main.name
    storage_account_name    = azurerm_storage_account.main.name
    stream_analytics_job    = azurerm_stream_analytics_job.main.name
    key_vault_name          = azurerm_key_vault.main.name
    edge_device_id          = azurerm_iothub_device.edge_device.device_id
    location                = azurerm_resource_group.main.location
    environment             = var.environment
    project_name            = var.project_name
  }
}

# Key Vault Secrets Reference
output "key_vault_secrets" {
  description = "List of secrets stored in Key Vault"
  value = {
    device_connection_string = azurerm_key_vault_secret.device_connection_string.name
    storage_connection_string = azurerm_key_vault_secret.storage_connection_string.name
    eventhub_connection_string = azurerm_key_vault_secret.eventhub_connection_string.name
  }
}

# Azure CLI Commands for Management
output "management_commands" {
  description = "Useful Azure CLI commands for managing the deployed resources"
  value = {
    start_stream_analytics = "az stream-analytics job start --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_stream_analytics_job.main.name}"
    stop_stream_analytics  = "az stream-analytics job stop --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_stream_analytics_job.main.name}"
    check_iothub_status    = "az iot hub show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_iothub.main.name}"
    list_edge_devices      = "az iot hub device-identity list --hub-name ${azurerm_iothub.main.name}"
    monitor_stream_job     = "az stream-analytics job show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_stream_analytics_job.main.name} --query 'jobState'"
  }
}

# URLs for Resource Management
output "azure_portal_urls" {
  description = "Azure Portal URLs for resource management"
  value = {
    resource_group = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    iothub         = "https://portal.azure.com/#@/resource${azurerm_iothub.main.id}/overview"
    ml_workspace   = "https://portal.azure.com/#@/resource${azurerm_machine_learning_workspace.main.id}/overview"
    stream_analytics = "https://portal.azure.com/#@/resource${azurerm_stream_analytics_job.main.id}/overview"
    key_vault      = "https://portal.azure.com/#@/resource${azurerm_key_vault.main.id}/overview"
  }
}