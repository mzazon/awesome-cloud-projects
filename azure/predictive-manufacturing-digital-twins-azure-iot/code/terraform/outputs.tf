# Output values for Azure smart manufacturing digital twins solution
# These outputs provide essential information for post-deployment configuration and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all manufacturing digital twins resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where the resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# IoT Hub Information
output "iot_hub_name" {
  description = "Name of the IoT Hub for device connectivity"
  value       = azurerm_iothub.main.name
}

output "iot_hub_hostname" {
  description = "IoT Hub hostname for device connections"
  value       = azurerm_iothub.main.hostname
}

output "iot_hub_event_hub_events_endpoint" {
  description = "Event Hub-compatible endpoint for telemetry consumption"
  value       = azurerm_iothub.main.event_hub_events_endpoint
}

output "iot_hub_event_hub_events_path" {
  description = "Event Hub-compatible path for telemetry consumption"
  value       = azurerm_iothub.main.event_hub_events_path
}

output "iot_hub_shared_access_policy_key" {
  description = "Primary key for IoT Hub shared access policy"
  value       = azurerm_iothub.main.shared_access_policy[0].primary_key
  sensitive   = true
}

output "iot_hub_resource_id" {
  description = "Resource ID of the IoT Hub"
  value       = azurerm_iothub.main.id
}

# Digital Twins Information
output "digital_twins_name" {
  description = "Name of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.main.name
}

output "digital_twins_host_name" {
  description = "Host name of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.main.host_name
}

output "digital_twins_resource_id" {
  description = "Resource ID of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.main.id
}

output "digital_twins_identity_principal_id" {
  description = "Principal ID of the Digital Twins managed identity"
  value       = azurerm_digital_twins_instance.main.identity[0].principal_id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for data persistence"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_dfs_endpoint" {
  description = "Primary Data Lake Storage Gen2 endpoint"
  value       = azurerm_storage_account.main.primary_dfs_endpoint
}

output "storage_account_resource_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

# Time Series Insights Information
output "tsi_environment_name" {
  description = "Name of the Time Series Insights environment"
  value       = azurerm_iot_time_series_insights_gen2_environment.main.name
}

output "tsi_environment_id" {
  description = "Resource ID of the Time Series Insights environment"
  value       = azurerm_iot_time_series_insights_gen2_environment.main.id
}

output "tsi_environment_data_access_fqdn" {
  description = "Data access FQDN for Time Series Insights environment"
  value       = azurerm_iot_time_series_insights_gen2_environment.main.data_access_fqdn
}

# Machine Learning Workspace Information
output "ml_workspace_name" {
  description = "Name of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.name
}

output "ml_workspace_id" {
  description = "Resource ID of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.id
}

output "ml_workspace_discovery_url" {
  description = "Discovery URL for the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.discovery_url
}

output "ml_workspace_identity_principal_id" {
  description = "Principal ID of the ML workspace managed identity"
  value       = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for secrets management"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_resource_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Monitoring and Diagnostics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_name" {
  description = "Name of the Application Insights component"
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

# Sample IoT Device Information (if created)
output "sample_device_ids" {
  description = "List of sample IoT device IDs created for testing"
  value       = var.create_sample_devices ? [for device in azurerm_iothub_device.sample_devices : device.name] : []
}

output "sample_device_connection_strings" {
  description = "Connection strings for sample IoT devices"
  value = var.create_sample_devices ? {
    for device in azurerm_iothub_device.sample_devices :
    device.name => device.primary_connection_string
  } : {}
  sensitive = true
}

# Configuration Information for Client Applications
output "iot_hub_connection_string_secret_name" {
  description = "Key Vault secret name containing IoT Hub connection string"
  value       = azurerm_key_vault_secret.iot_hub_connection.name
}

output "storage_connection_string_secret_name" {
  description = "Key Vault secret name containing storage account connection string"
  value       = azurerm_key_vault_secret.storage_connection.name
}

# Azure CLI Commands for Post-Deployment Configuration
output "az_cli_login_command" {
  description = "Azure CLI command to login and set subscription"
  value       = "az login && az account set --subscription ${data.azurerm_client_config.current.subscription_id}"
}

output "digital_twins_cli_setup_commands" {
  description = "Azure CLI commands to set up Digital Twins CLI extension and context"
  value = [
    "az extension add --name azure-iot",
    "az extension add --name dt",
    "az dt endpoint create eventgrid --dt-name ${azurerm_digital_twins_instance.main.name} --eventgrid-resource-group ${azurerm_resource_group.main.name} --eventgrid-topic my-eventgrid-topic --endpoint-name my-endpoint"
  ]
}

output "iot_device_simulation_commands" {
  description = "Azure CLI commands for IoT device simulation"
  value = var.create_sample_devices ? [
    for device in azurerm_iothub_device.sample_devices :
    "az iot device simulate --device-id ${device.name} --hub-name ${azurerm_iothub.main.name} --data '{\"temperature\": 25.0, \"humidity\": 60.0}'"
  ] : []
}

# Digital Twins Model Upload Commands
output "digital_twins_model_upload_examples" {
  description = "Example commands for uploading DTDL models to Digital Twins"
  value = [
    "# Create production line model file and upload:",
    "az dt model create --dt-name ${azurerm_digital_twins_instance.main.name} --models ./production-line-model.json",
    "# Create equipment model file and upload:",
    "az dt model create --dt-name ${azurerm_digital_twins_instance.main.name} --models ./equipment-model.json",
    "# Create digital twin instances:",
    "az dt twin create --dt-name ${azurerm_digital_twins_instance.main.name} --dtmi 'dtmi:manufacturing:ProductionLine;1' --twin-id 'production-line-a'",
    "az dt twin create --dt-name ${azurerm_digital_twins_instance.main.name} --dtmi 'dtmi:manufacturing:Equipment;1' --twin-id 'robotic-arm-001'"
  ]
}

# Time Series Insights Access Information
output "tsi_access_information" {
  description = "Information for accessing Time Series Insights"
  value = {
    environment_name = azurerm_iot_time_series_insights_gen2_environment.main.name
    data_access_fqdn = azurerm_iot_time_series_insights_gen2_environment.main.data_access_fqdn
    time_series_id   = var.tsi_time_series_id_properties
    warm_store_retention = var.tsi_warm_store_retention
  }
}

# Machine Learning Development Information
output "ml_development_information" {
  description = "Information for Machine Learning development"
  value = {
    workspace_name   = azurerm_machine_learning_workspace.main.name
    discovery_url    = azurerm_machine_learning_workspace.main.discovery_url
    resource_group   = azurerm_resource_group.main.name
    subscription_id  = data.azurerm_client_config.current.subscription_id
    data_sources = {
      iot_hub_name     = azurerm_iothub.main.name
      storage_account  = azurerm_storage_account.main.name
      tsi_environment  = azurerm_iot_time_series_insights_gen2_environment.main.name
    }
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the deployed smart manufacturing digital twins solution"
  value = {
    solution_name           = "Smart Manufacturing Digital Twins"
    environment            = var.environment
    location               = var.location
    resource_group         = azurerm_resource_group.main.name
    total_sample_devices   = var.create_sample_devices ? length(var.sample_devices) : 0
    iot_hub_sku           = "${var.iot_hub_sku.name}:${var.iot_hub_sku.capacity}"
    tsi_sku               = "${var.tsi_sku.name}:${var.tsi_sku.capacity}"
    ml_workspace_sku      = var.ml_workspace_sku
    storage_tier          = var.storage_account_tier
    storage_replication   = var.storage_account_replication
    diagnostics_enabled   = var.enable_diagnostics
    rbac_enabled          = var.enable_rbac_assignments
    auto_delete_enabled   = var.auto_delete_resources
  }
}

# Cost Management Information
output "cost_management_tags" {
  description = "Tags applied to all resources for cost tracking and management"
  value       = local.common_tags
}

output "estimated_monthly_cost_note" {
  description = "Note about estimated monthly costs"
  value = "Estimated monthly cost varies based on usage. Key cost factors: IoT Hub messages, TSI data ingestion/storage, ML compute usage, and storage transactions. Monitor costs using Azure Cost Management."
}