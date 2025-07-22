# Outputs for Smart Factory Carbon Footprint Monitoring Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all smart factory resources"
  value       = azurerm_resource_group.smart_factory.name
}

output "resource_group_location" {
  description = "Azure region where the resources are deployed"
  value       = azurerm_resource_group.smart_factory.location
}

# IoT Hub Outputs
output "iot_hub_name" {
  description = "Name of the IoT Hub for industrial device connectivity"
  value       = azurerm_iothub.factory_iot_hub.name
}

output "iot_hub_hostname" {
  description = "Hostname of the IoT Hub for device connections"
  value       = azurerm_iothub.factory_iot_hub.hostname
}

output "iot_hub_primary_key" {
  description = "Primary key for IoT Hub access (sensitive)"
  value       = azurerm_iothub.factory_iot_hub.shared_access_policy[0].primary_key
  sensitive   = true
}

output "iot_hub_connection_string" {
  description = "Connection string for IoT Hub service access (sensitive)"
  value       = "HostName=${azurerm_iothub.factory_iot_hub.hostname};SharedAccessKeyName=iothubowner;SharedAccessKey=${azurerm_iothub.factory_iot_hub.shared_access_policy[0].primary_key}"
  sensitive   = true
}

output "iot_device_id" {
  description = "ID of the sample IoT device for testing"
  value       = azurerm_iothub_device.factory_sensor.device_id
}

output "iot_device_primary_key" {
  description = "Primary key for the sample IoT device (sensitive)"
  value       = azurerm_iothub_device.factory_sensor.primary_key
  sensitive   = true
}

output "iot_device_connection_string" {
  description = "Connection string for the sample IoT device (sensitive)"
  value       = "HostName=${azurerm_iothub.factory_iot_hub.hostname};DeviceId=${azurerm_iothub_device.factory_sensor.device_id};SharedAccessKey=${azurerm_iothub_device.factory_sensor.primary_key}"
  sensitive   = true
}

# Event Hub Outputs
output "eventhub_namespace_name" {
  description = "Name of the Event Hubs namespace for carbon data ingestion"
  value       = azurerm_eventhub_namespace.carbon_events.name
}

output "eventhub_name" {
  description = "Name of the Event Hub for carbon telemetry data"
  value       = azurerm_eventhub.carbon_telemetry.name
}

output "eventhub_connection_string" {
  description = "Connection string for Event Hub access (sensitive)"
  value       = azurerm_eventhub_authorization_rule.carbon_data.primary_connection_string
  sensitive   = true
}

output "eventhub_primary_key" {
  description = "Primary key for Event Hub access (sensitive)"
  value       = azurerm_eventhub_authorization_rule.carbon_data.primary_key
  sensitive   = true
}

# Event Grid Outputs
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic for carbon monitoring events"
  value       = azurerm_eventgrid_topic.carbon_monitoring.name
}

output "event_grid_endpoint" {
  description = "Endpoint URL for the Event Grid topic"
  value       = azurerm_eventgrid_topic.carbon_monitoring.endpoint
}

output "event_grid_access_key" {
  description = "Access key for Event Grid topic (sensitive)"
  value       = azurerm_eventgrid_topic.carbon_monitoring.primary_access_key
  sensitive   = true
}

# Data Explorer (Kusto) Outputs
output "kusto_cluster_name" {
  description = "Name of the Data Explorer cluster for carbon analytics"
  value       = azurerm_kusto_cluster.carbon_analytics.name
}

output "kusto_cluster_uri" {
  description = "URI of the Data Explorer cluster for query access"
  value       = azurerm_kusto_cluster.carbon_analytics.uri
}

output "kusto_database_name" {
  description = "Name of the Data Explorer database for carbon monitoring data"
  value       = azurerm_kusto_database.carbon_monitoring.name
}

output "kusto_data_ingestion_uri" {
  description = "Data ingestion URI for the Data Explorer cluster"
  value       = azurerm_kusto_cluster.carbon_analytics.data_ingestion_uri
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Function App for carbon calculations"
  value       = azurerm_linux_function_app.carbon_calculator.name
}

output "function_app_hostname" {
  description = "Hostname of the Function App for API access"
  value       = azurerm_linux_function_app.carbon_calculator.default_hostname
}

output "function_app_url" {
  description = "Base URL of the Function App"
  value       = "https://${azurerm_linux_function_app.carbon_calculator.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.carbon_calculator.identity[0].principal_id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for factory data"
  value       = azurerm_storage_account.factory_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.factory_storage.primary_blob_endpoint
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account (sensitive)"
  value       = azurerm_storage_account.factory_storage.primary_access_key
  sensitive   = true
}

output "storage_containers" {
  description = "List of storage containers created for different data types"
  value = {
    carbon_data          = azurerm_storage_container.carbon_data.name
    carbon_archive       = azurerm_storage_container.carbon_archive.name
    file_uploads         = azurerm_storage_container.file_uploads.name
    sustainability_reports = azurerm_storage_container.sustainability_reports.name
  }
}

# Monitoring Outputs (if enabled)
output "application_insights_name" {
  description = "Name of Application Insights for monitoring (if enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.carbon_monitoring[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive, if enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.carbon_monitoring[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive, if enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.carbon_monitoring[0].connection_string : null
  sensitive   = true
}

# Configuration and Setup Information
output "carbon_emission_factor" {
  description = "Carbon emission factor configured for calculations (kg CO2/kWh)"
  value       = var.carbon_emission_factor
}

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    iot_hub           = "Industrial device connectivity and telemetry ingestion"
    event_hub         = "High-throughput event streaming and data capture"
    event_grid        = "Event-driven architecture and workflow orchestration"
    data_explorer     = "Real-time analytics and time-series data storage"
    function_app      = "Serverless carbon footprint calculation logic"
    storage_account   = "Blob storage for data archive and file uploads"
    monitoring        = var.enable_monitoring ? "Application Insights for performance monitoring" : "Monitoring disabled"
    backup_vault      = var.enable_backup ? "Recovery Services Vault for data protection" : "Backup disabled"
  }
}

# Environment Configuration
output "environment_variables" {
  description = "Environment variables for client applications and testing"
  value = {
    AZURE_RESOURCE_GROUP     = azurerm_resource_group.smart_factory.name
    AZURE_LOCATION          = azurerm_resource_group.smart_factory.location
    IOT_HUB_NAME           = azurerm_iothub.factory_iot_hub.name
    IOT_HUB_HOSTNAME       = azurerm_iothub.factory_iot_hub.hostname
    EVENTHUB_NAMESPACE     = azurerm_eventhub_namespace.carbon_events.name
    EVENTHUB_NAME          = azurerm_eventhub.carbon_telemetry.name
    EVENT_GRID_TOPIC       = azurerm_eventgrid_topic.carbon_monitoring.name
    KUSTO_CLUSTER_NAME     = azurerm_kusto_cluster.carbon_analytics.name
    KUSTO_DATABASE_NAME    = azurerm_kusto_database.carbon_monitoring.name
    FUNCTION_APP_NAME      = azurerm_linux_function_app.carbon_calculator.name
    STORAGE_ACCOUNT_NAME   = azurerm_storage_account.factory_storage.name
  }
}

# Sample Connection Commands
output "sample_device_commands" {
  description = "Sample commands for testing IoT device connectivity"
  value = {
    send_telemetry = "az iot device send-d2c-message --hub-name ${azurerm_iothub.factory_iot_hub.name} --device-id ${azurerm_iothub_device.factory_sensor.device_id} --data '{\"deviceId\":\"${azurerm_iothub_device.factory_sensor.device_id}\",\"timestamp\":\"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\",\"telemetry\":{\"energyKwh\":15.5,\"productionUnits\":100,\"temperature\":22.5,\"humidity\":45}}'"
    monitor_events = "az iot hub monitor-events --hub-name ${azurerm_iothub.factory_iot_hub.name} --device-id ${azurerm_iothub_device.factory_sensor.device_id}"
  }
}

# Security and Access Information
output "security_configuration" {
  description = "Security features and access control information"
  value = {
    managed_identity_enabled = "Function App uses managed identity for secure access"
    private_endpoints        = var.enable_private_endpoints ? "Private endpoints enabled for enhanced security" : "Private endpoints disabled"
    storage_encryption      = "Storage account encrypted with Microsoft-managed keys"
    tls_version            = "Minimum TLS 1.2 enforced on all endpoints"
    public_access          = "Storage account public access disabled"
  }
}

# Cost and Scaling Information
output "cost_optimization_notes" {
  description = "Information about cost optimization features"
  value = {
    function_app_plan      = "Using ${var.function_app_sku_tier} tier for cost-effective scaling"
    storage_tier          = "Using ${var.storage_account_tier} tier storage with ${var.storage_account_replication_type} replication"
    iot_hub_tier          = "Using ${var.iot_hub_sku} tier IoT Hub with ${var.iot_hub_capacity} unit(s)"
    eventhub_tier         = "Using ${var.eventhub_sku} tier Event Hubs with ${var.eventhub_capacity} throughput unit(s)"
    kusto_autoscale       = "Data Explorer cluster configured with auto-scale enabled"
    data_retention        = "Data retention set to ${var.kusto_database_retention_period}"
  }
}

# Next Steps and Documentation
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Deploy carbon calculation function code to the Function App",
    "2. Configure IoT devices with the provided connection strings",
    "3. Set up Data Explorer tables and ingestion mappings",
    "4. Configure monitoring dashboards and alerts",
    "5. Test end-to-end data flow from devices to analytics",
    "6. Implement sustainability reporting and compliance workflows"
  ]
}