# Output values for Azure precision agriculture analytics platform
# These outputs provide essential information for application configuration and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all agriculture resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the main resource group"
  value       = azurerm_resource_group.main.id
}

# Azure Data Manager for Agriculture Outputs
output "adma_instance_name" {
  description = "Name of the Azure Data Manager for Agriculture instance"
  value       = local.adma_name
}

output "adma_endpoint" {
  description = "API endpoint URL for Azure Data Manager for Agriculture"
  value       = azurerm_template_deployment.adma.outputs["admaEndpoint"]
  sensitive   = false
}

# IoT Hub Outputs
output "iot_hub_name" {
  description = "Name of the IoT Hub for sensor data ingestion"
  value       = azurerm_iothub.main.name
}

output "iot_hub_hostname" {
  description = "Hostname of the IoT Hub"
  value       = azurerm_iothub.main.hostname
}

output "iot_hub_connection_string" {
  description = "Primary connection string for IoT Hub"
  value       = azurerm_iothub.main.shared_access_policy[0].connection_string
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

output "sample_iot_device_id" {
  description = "ID of the sample IoT device created for demonstration"
  value       = azurerm_iothub_device.sample_sensor.device_id
}

output "sample_iot_device_primary_key" {
  description = "Primary key for the sample IoT device"
  value       = azurerm_iothub_device.sample_sensor.primary_key
  sensitive   = true
}

output "sample_iot_device_secondary_key" {
  description = "Secondary key for the sample IoT device"
  value       = azurerm_iothub_device.sample_sensor.secondary_key
  sensitive   = true
}

output "sample_iot_device_connection_string" {
  description = "Connection string for the sample IoT device"
  value       = "HostName=${azurerm_iothub.main.hostname};DeviceId=${azurerm_iothub_device.sample_sensor.device_id};SharedAccessKey=${azurerm_iothub_device.sample_sensor.primary_key}"
  sensitive   = true
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for agricultural data"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint URL for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_containers" {
  description = "List of storage containers created for agricultural data"
  value = {
    for container in azurerm_storage_container.agricultural_data : 
    container.name => {
      name = container.name
      url  = "${azurerm_storage_account.main.primary_blob_endpoint}${container.name}"
    }
  }
}

# Azure AI Services (Cognitive Services) Outputs
output "ai_services_name" {
  description = "Name of the Azure AI Services (Cognitive Services) account"
  value       = azurerm_cognitive_account.main.name
}

output "ai_services_endpoint" {
  description = "Endpoint URL for Azure AI Services"
  value       = azurerm_cognitive_account.main.endpoint
}

output "ai_services_primary_access_key" {
  description = "Primary access key for Azure AI Services"
  value       = azurerm_cognitive_account.main.primary_access_key
  sensitive   = true
}

output "ai_services_secondary_access_key" {
  description = "Secondary access key for Azure AI Services"
  value       = azurerm_cognitive_account.main.secondary_access_key
  sensitive   = true
}

# Azure Maps Outputs
output "maps_account_name" {
  description = "Name of the Azure Maps account"
  value       = azurerm_maps_account.main.name
}

output "maps_primary_access_key" {
  description = "Primary access key for Azure Maps"
  value       = azurerm_maps_account.main.primary_access_key
  sensitive   = true
}

output "maps_secondary_access_key" {
  description = "Secondary access key for Azure Maps"
  value       = azurerm_maps_account.main.secondary_access_key
  sensitive   = true
}

# Stream Analytics Outputs
output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.name
}

output "stream_analytics_job_id" {
  description = "Resource ID of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.id
}

output "stream_analytics_streaming_units" {
  description = "Number of streaming units configured for the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.streaming_units
}

# Azure Function App Outputs
output "function_app_name" {
  description = "Name of the Azure Function App for image processing"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "app_service_plan_name" {
  description = "Name of the App Service Plan hosting the Function App"
  value       = azurerm_service_plan.main.name
}

# Monitoring and Diagnostics Outputs (if enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if diagnostic settings enabled)"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if diagnostic settings enabled)"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.main[0].id : null
}

output "application_insights_name" {
  description = "Name of the Application Insights instance (if diagnostic settings enabled)"
  value       = var.enable_diagnostic_settings ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if diagnostic settings enabled)"
  value       = var.enable_diagnostic_settings ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if diagnostic settings enabled)"
  value       = var.enable_diagnostic_settings ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Cost Management Outputs (if enabled)
output "budget_name" {
  description = "Name of the cost management budget (if cost alerts enabled)"
  value       = var.enable_cost_alerts ? azurerm_consumption_budget_resource_group.main[0].name : null
}

output "monthly_budget_limit" {
  description = "Monthly budget limit in USD (if cost alerts enabled)"
  value       = var.enable_cost_alerts ? var.monthly_budget_limit : null
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

# Configuration Information for Applications
output "application_configuration" {
  description = "Complete configuration object for precision agriculture applications"
  value = {
    resource_group = {
      name     = azurerm_resource_group.main.name
      location = azurerm_resource_group.main.location
    }
    
    data_manager = {
      name     = local.adma_name
      endpoint = azurerm_template_deployment.adma.outputs["admaEndpoint"]
    }
    
    iot_hub = {
      name     = azurerm_iothub.main.name
      hostname = azurerm_iothub.main.hostname
    }
    
    storage = {
      account_name = azurerm_storage_account.main.name
      endpoint     = azurerm_storage_account.main.primary_blob_endpoint
      containers   = var.storage_containers
    }
    
    ai_services = {
      name     = azurerm_cognitive_account.main.name
      endpoint = azurerm_cognitive_account.main.endpoint
    }
    
    maps = {
      account_name = azurerm_maps_account.main.name
    }
    
    stream_analytics = {
      job_name = azurerm_stream_analytics_job.main.name
    }
    
    function_app = {
      name     = azurerm_linux_function_app.main.name
      hostname = azurerm_linux_function_app.main.default_hostname
    }
  }
  sensitive = false
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Commands to get started with the deployed infrastructure"
  value = {
    test_iot_device = "az iot device simulate --hub-name ${azurerm_iothub.main.name} --device-id ${azurerm_iothub_device.sample_sensor.device_id} --data '{\"temperature\": 25.5, \"humidity\": 60.2}'"
    
    start_stream_analytics = "az stream-analytics job start --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_stream_analytics_job.main.name}"
    
    upload_test_image = "az storage blob upload --account-name ${azurerm_storage_account.main.name} --container-name ${var.storage_containers[0]} --name test-crop-image.jpg --file /path/to/image.jpg"
    
    view_function_logs = "az functionapp log tail --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Security Information
output "security_considerations" {
  description = "Important security considerations for the deployed infrastructure"
  value = {
    network_access = "Review and configure network access rules for production use"
    key_rotation   = "Implement regular rotation of access keys and connection strings"
    rbac          = "Configure Role-Based Access Control (RBAC) for fine-grained permissions"
    monitoring    = "Enable security monitoring and alerting through Azure Security Center"
    compliance    = "Review compliance requirements for agricultural data handling"
  }
}