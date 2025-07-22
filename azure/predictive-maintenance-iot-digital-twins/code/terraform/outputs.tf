# Resource Group Output
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Azure Digital Twins Outputs
output "digital_twins_name" {
  description = "Name of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.main.name
}

output "digital_twins_id" {
  description = "ID of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.main.id
}

output "digital_twins_host_name" {
  description = "Host name of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.main.host_name
}

output "digital_twins_endpoint_url" {
  description = "Service URL of the Azure Digital Twins instance"
  value       = "https://${azurerm_digital_twins_instance.main.host_name}"
}

output "digital_twins_explorer_url" {
  description = "URL for Azure Digital Twins Explorer"
  value       = "https://explorer.digitaltwins.azure.net/?tid=${data.azurerm_client_config.current.tenant_id}&eid=${azurerm_digital_twins_instance.main.host_name}"
}

# IoT Central Outputs
output "iot_central_name" {
  description = "Name of the IoT Central application"
  value       = azurerm_iotcentral_application.main.name
}

output "iot_central_id" {
  description = "ID of the IoT Central application"
  value       = azurerm_iotcentral_application.main.id
}

output "iot_central_application_url" {
  description = "URL of the IoT Central application"
  value       = "https://${azurerm_iotcentral_application.main.sub_domain}.azureiotcentral.com"
}

output "iot_central_subdomain" {
  description = "Subdomain of the IoT Central application"
  value       = azurerm_iotcentral_application.main.sub_domain
}

# Event Hub Outputs
output "event_hub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "event_hub_namespace_id" {
  description = "ID of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.id
}

output "event_hub_name" {
  description = "Name of the Event Hub"
  value       = azurerm_eventhub.telemetry.name
}

output "event_hub_id" {
  description = "ID of the Event Hub"
  value       = azurerm_eventhub.telemetry.id
}

output "event_hub_connection_string" {
  description = "Primary connection string for Event Hub"
  value       = azurerm_eventhub_authorization_rule.main.primary_connection_string
  sensitive   = true
}

output "event_hub_connection_string_secondary" {
  description = "Secondary connection string for Event Hub"
  value       = azurerm_eventhub_authorization_rule.main.secondary_connection_string
  sensitive   = true
}

# Azure Data Explorer Outputs
output "data_explorer_cluster_name" {
  description = "Name of the Azure Data Explorer cluster"
  value       = azurerm_kusto_cluster.main.name
}

output "data_explorer_cluster_id" {
  description = "ID of the Azure Data Explorer cluster"
  value       = azurerm_kusto_cluster.main.id
}

output "data_explorer_cluster_uri" {
  description = "URI of the Azure Data Explorer cluster"
  value       = azurerm_kusto_cluster.main.uri
}

output "data_explorer_database_name" {
  description = "Name of the Azure Data Explorer database"
  value       = azurerm_kusto_database.main.name
}

output "data_explorer_database_id" {
  description = "ID of the Azure Data Explorer database"
  value       = azurerm_kusto_database.main.id
}

output "data_explorer_web_ui_url" {
  description = "URL for Azure Data Explorer Web UI"
  value       = "https://dataexplorer.azure.com/clusters/${azurerm_kusto_cluster.main.name}"
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "Default hostname of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.function_storage.id
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.function_storage.primary_connection_string
  sensitive   = true
}

# Time Series Insights Outputs
output "time_series_insights_name" {
  description = "Name of the Time Series Insights environment"
  value       = azurerm_iot_time_series_insights_gen2_environment.main.name
}

output "time_series_insights_id" {
  description = "ID of the Time Series Insights environment"
  value       = azurerm_iot_time_series_insights_gen2_environment.main.id
}

output "time_series_insights_data_access_fqdn" {
  description = "FQDN for Time Series Insights data access"
  value       = azurerm_iot_time_series_insights_gen2_environment.main.data_access_fqdn
}

# Log Analytics Workspace Outputs (if enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Digital Twins Endpoint Outputs
output "digital_twins_endpoint_name" {
  description = "Name of the Digital Twins Event Hub endpoint"
  value       = azurerm_digital_twins_endpoint_eventhub.main.name
}

output "digital_twins_endpoint_id" {
  description = "ID of the Digital Twins Event Hub endpoint"
  value       = azurerm_digital_twins_endpoint_eventhub.main.id
}

# Data Connection Outputs
output "data_connection_name" {
  description = "Name of the Event Hub data connection"
  value       = azurerm_kusto_eventhub_data_connection.main.name
}

output "data_connection_id" {
  description = "ID of the Event Hub data connection"
  value       = azurerm_kusto_eventhub_data_connection.main.id
}

# Kusto Queries for Reference
output "kusto_queries" {
  description = "Sample Kusto queries for data analysis"
  value = {
    anomaly_detection = "TelemetryData | where Timestamp > ago(1h) | make-series Temperature=avg(Temperature) default=0 on Timestamp step 1m by DeviceId | extend (anomalies, score, baseline) = series_decompose_anomalies(Temperature, 1.5, -1, 'linefit') | mv-expand Timestamp, Temperature, anomalies, score, baseline | where anomalies == 1 | project DeviceId, Timestamp, Temperature, score, baseline"
    
    maintenance_prediction = "TelemetryData | where Timestamp > ago(7d) | summarize AvgVibration=avg(Vibration), MaxVibration=max(Vibration), OperatingHours=max(OperatingHours) by DeviceId | extend MaintenanceRisk = case(MaxVibration > 50 and OperatingHours > 1000, 'High', MaxVibration > 30 and OperatingHours > 500, 'Medium', 'Low') | project DeviceId, MaintenanceRisk, AvgVibration, OperatingHours"
    
    device_health_summary = "TelemetryData | where Timestamp > ago(1d) | summarize LastSeen=max(Timestamp), AvgTemperature=avg(Temperature), AvgVibration=avg(Vibration), MaxOperatingHours=max(OperatingHours) by DeviceId | extend Status = case(LastSeen < ago(1h), 'Offline', AvgTemperature > 60, 'Warning', 'Healthy') | project DeviceId, Status, LastSeen, AvgTemperature, AvgVibration, MaxOperatingHours"
  }
}

# Digital Twin Model Information
output "digital_twin_model_info" {
  description = "Information about the digital twin model"
  value = {
    model_id = var.digital_twin_model_id
    model_definition = jsonencode({
      "@id" = var.digital_twin_model_id
      "@type" = "Interface"
      "@context" = "dtmi:dtdl:context;2"
      "displayName" = "Industrial Equipment"
      "contents" = [
        {
          "@type" = "Property"
          "name" = "temperature"
          "schema" = "double"
        },
        {
          "@type" = "Property"
          "name" = "vibration"
          "schema" = "double"
        },
        {
          "@type" = "Property"
          "name" = "operatingHours"
          "schema" = "integer"
        },
        {
          "@type" = "Property"
          "name" = "maintenanceStatus"
          "schema" = "string"
        }
      ]
    })
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration values"
  value = {
    resource_group_name = azurerm_resource_group.main.name
    location = azurerm_resource_group.main.location
    digital_twins_name = azurerm_digital_twins_instance.main.name
    iot_central_name = azurerm_iotcentral_application.main.name
    data_explorer_cluster = azurerm_kusto_cluster.main.name
    function_app_name = azurerm_linux_function_app.main.name
    event_hub_namespace = azurerm_eventhub_namespace.main.name
    diagnostic_logs_enabled = var.enable_diagnostic_logs
    environment = var.environment
    generated_suffix = random_string.suffix.result
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps for using the deployed infrastructure"
  value = {
    digital_twins_explorer = "Visit the Digital Twins Explorer to upload models and create twins: https://explorer.digitaltwins.azure.net/"
    iot_central_setup = "Configure device templates and devices in IoT Central: https://${azurerm_iotcentral_application.main.sub_domain}.azureiotcentral.com"
    data_explorer_queries = "Run analytics queries in Data Explorer: https://dataexplorer.azure.com/clusters/${azurerm_kusto_cluster.main.name}"
    function_app_deployment = "Deploy Function App code for twin updates and analytics processing"
    monitoring_setup = "Configure alerts and dashboards in Azure Monitor for proactive monitoring"
  }
}