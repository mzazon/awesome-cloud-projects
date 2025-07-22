# Output values for Azure Orbital and Azure Local edge-to-orbit data processing infrastructure
# These outputs provide important information for accessing and managing the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_string.suffix.result
}

# IoT Hub Information
output "iot_hub_name" {
  description = "Name of the IoT Hub for satellite telemetry"
  value       = azurerm_iothub.main.name
}

output "iot_hub_hostname" {
  description = "Hostname of the IoT Hub"
  value       = azurerm_iothub.main.hostname
}

output "iot_hub_primary_connection_string" {
  description = "Primary connection string for IoT Hub"
  value       = azurerm_iothub.main.primary_connection_string
  sensitive   = true
}

output "iot_hub_event_hub_endpoint" {
  description = "Event Hub-compatible endpoint for IoT Hub"
  value       = azurerm_iothub.main.event_hub_events_endpoint
}

output "iot_hub_event_hub_path" {
  description = "Event Hub-compatible path for IoT Hub"
  value       = azurerm_iothub.main.event_hub_events_path
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for satellite data"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_containers" {
  description = "List of created storage containers"
  value = {
    telemetry = azurerm_storage_container.telemetry.name
    imagery   = azurerm_storage_container.imagery.name
    analytics = azurerm_storage_container.analytics.name
  }
}

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic for orbital events"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL for Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_topic_primary_key" {
  description = "Primary access key for Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App for satellite data processing"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_default_hostname" {
  description = "Default hostname for Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_outbound_ip_addresses" {
  description = "Outbound IP addresses for Function App"
  value       = azurerm_linux_function_app.main.outbound_ip_addresses
}

# Azure Orbital Information
output "spacecraft_name" {
  description = "Name of the registered spacecraft"
  value       = azurerm_orbital_spacecraft.main.name
}

output "spacecraft_norad_id" {
  description = "NORAD ID of the registered spacecraft"
  value       = azurerm_orbital_spacecraft.main.norad_id
}

output "contact_profile_name" {
  description = "Name of the orbital contact profile"
  value       = azurerm_orbital_contact_profile.main.name
}

output "contact_profile_minimum_elevation" {
  description = "Minimum elevation angle for satellite contacts"
  value       = azurerm_orbital_contact_profile.main.minimum_elevation_degrees
}

output "contact_profile_minimum_duration" {
  description = "Minimum viable contact duration"
  value       = azurerm_orbital_contact_profile.main.minimum_viable_contact_duration
}

# Azure Local Information (if enabled)
output "azure_local_cluster_name" {
  description = "Name of the Azure Local cluster"
  value       = var.enable_azure_local ? azurerm_stack_hci_cluster.main[0].name : null
}

output "azure_local_cluster_id" {
  description = "Resource ID of the Azure Local cluster"
  value       = var.enable_azure_local ? azurerm_stack_hci_cluster.main[0].id : null
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Security Information
output "key_vault_name" {
  description = "Name of the Key Vault for secrets management"
  value       = var.enable_key_vault ? azurerm_key_vault.main[0].name : null
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = var.enable_key_vault ? azurerm_key_vault.main[0].vault_uri : null
}

output "key_vault_secrets" {
  description = "List of secrets stored in Key Vault"
  value = var.enable_key_vault ? {
    iot_connection_string     = azurerm_key_vault_secret.iot_connection_string[0].name
    storage_connection_string = azurerm_key_vault_secret.storage_connection_string[0].name
    event_grid_key           = azurerm_key_vault_secret.event_grid_key[0].name
  } : {}
}

# Network Information
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : null
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].id : null
}

output "subnet_ids" {
  description = "Resource IDs of the created subnets"
  value = var.enable_private_endpoints ? {
    orbital  = azurerm_subnet.orbital[0].id
    function = azurerm_subnet.function[0].id
    storage  = azurerm_subnet.storage[0].id
    local    = azurerm_subnet.local[0].id
  } : {}
}

# AI Services Information (if enabled)
output "cognitive_services_name" {
  description = "Name of the Cognitive Services account"
  value       = var.enable_ai_services ? azurerm_cognitive_account.main[0].name : null
}

output "cognitive_services_endpoint" {
  description = "Endpoint URL for Cognitive Services"
  value       = var.enable_ai_services ? azurerm_cognitive_account.main[0].endpoint : null
}

# Data Factory Information (if enabled)
output "data_factory_name" {
  description = "Name of the Data Factory"
  value       = var.enable_data_lake_analytics ? azurerm_data_factory.main[0].name : null
}

output "data_factory_id" {
  description = "Resource ID of the Data Factory"
  value       = var.enable_data_lake_analytics ? azurerm_data_factory.main[0].id : null
}

# Backup Information (if enabled)
output "backup_vault_name" {
  description = "Name of the backup vault"
  value       = var.enable_disaster_recovery ? azurerm_data_protection_backup_vault.main[0].name : null
}

output "backup_vault_id" {
  description = "Resource ID of the backup vault"
  value       = var.enable_disaster_recovery ? azurerm_data_protection_backup_vault.main[0].id : null
}

# Connection Information for Applications
output "satellite_telemetry_connection_info" {
  description = "Connection information for satellite telemetry ingestion"
  value = {
    iot_hub_hostname     = azurerm_iothub.main.hostname
    event_hub_endpoint   = azurerm_iothub.main.event_hub_events_endpoint
    event_hub_path       = azurerm_iothub.main.event_hub_events_path
    storage_account_name = azurerm_storage_account.main.name
    telemetry_container  = azurerm_storage_container.telemetry.name
  }
}

output "orbital_ground_station_info" {
  description = "Information for orbital ground station configuration"
  value = {
    spacecraft_name             = azurerm_orbital_spacecraft.main.name
    contact_profile_name        = azurerm_orbital_contact_profile.main.name
    center_frequency_mhz        = var.center_frequency_mhz
    bandwidth_mhz               = var.bandwidth_mhz
    minimum_elevation_degrees   = var.minimum_elevation_degrees
    minimum_contact_duration    = var.minimum_contact_duration
  }
}

output "edge_processing_info" {
  description = "Information for edge processing configuration"
  value = {
    function_app_name    = azurerm_linux_function_app.main.name
    function_app_url     = "https://${azurerm_linux_function_app.main.default_hostname}"
    azure_local_cluster  = var.enable_azure_local ? azurerm_stack_hci_cluster.main[0].name : "not_enabled"
    event_grid_endpoint  = azurerm_eventgrid_topic.main.endpoint
  }
}

output "monitoring_dashboard_info" {
  description = "Information for monitoring dashboard configuration"
  value = var.enable_monitoring ? {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
    application_insights_key   = azurerm_application_insights.main[0].instrumentation_key
    resource_group_name        = azurerm_resource_group.main.name
    location                   = azurerm_resource_group.main.location
  } : null
}

# Resource Tags
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}

# Cost Management Information
output "cost_management_info" {
  description = "Information for cost management and optimization"
  value = {
    iot_hub_sku              = var.iot_hub_sku
    storage_account_tier     = var.storage_account_tier
    function_app_plan_sku    = var.function_app_service_plan_sku
    data_retention_days      = var.satellite_data_retention_days
    log_retention_days       = var.log_analytics_retention_days
    estimated_monthly_cost   = "Contact Azure pricing calculator for current rates"
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and configuration"
  value = {
    project_name                = var.project_name
    environment                = var.environment
    deployment_id              = random_string.suffix.result
    resource_group_name        = azurerm_resource_group.main.name
    location                   = azurerm_resource_group.main.location
    iot_hub_name               = azurerm_iothub.main.name
    spacecraft_name            = azurerm_orbital_spacecraft.main.name
    storage_account_name       = azurerm_storage_account.main.name
    function_app_name          = azurerm_linux_function_app.main.name
    event_grid_topic_name      = azurerm_eventgrid_topic.main.name
    azure_local_enabled        = var.enable_azure_local
    monitoring_enabled         = var.enable_monitoring
    private_endpoints_enabled  = var.enable_private_endpoints
    ai_services_enabled        = var.enable_ai_services
    disaster_recovery_enabled  = var.enable_disaster_recovery
    deployment_timestamp       = timestamp()
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Commands to quickly test the deployment"
  value = {
    test_iot_connectivity = "az iot device send-d2c-message --hub-name ${azurerm_iothub.main.name} --device-id test-satellite --data '{\"temperature\":25.5,\"altitude\":408000}'"
    list_storage_containers = "az storage container list --account-name ${azurerm_storage_account.main.name} --auth-mode login"
    monitor_function_logs = "az functionapp logs tail --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    view_satellite_contacts = "az orbital contact list --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Documentation Links
output "documentation_links" {
  description = "Links to relevant Azure documentation"
  value = {
    azure_orbital_docs = "https://docs.microsoft.com/en-us/azure/orbital/"
    azure_local_docs   = "https://docs.microsoft.com/en-us/azure/azure-local/"
    iot_hub_docs       = "https://docs.microsoft.com/en-us/azure/iot-hub/"
    event_grid_docs    = "https://docs.microsoft.com/en-us/azure/event-grid/"
    function_apps_docs = "https://docs.microsoft.com/en-us/azure/azure-functions/"
  }
}