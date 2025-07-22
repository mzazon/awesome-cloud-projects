# Output values for Azure Energy Grid Analytics Infrastructure
# These outputs provide essential information for accessing and managing the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all energy analytics resources"
  value       = azurerm_resource_group.energy_analytics.name
}

output "resource_group_id" {
  description = "ID of the resource group containing all energy analytics resources"
  value       = azurerm_resource_group.energy_analytics.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.energy_analytics.location
}

# Azure Data Manager for Energy Information
output "energy_data_manager_name" {
  description = "Name of the Azure Data Manager for Energy instance"
  value       = jsondecode(azapi_resource.energy_data_manager.output).name
}

output "energy_data_manager_id" {
  description = "ID of the Azure Data Manager for Energy instance"
  value       = azapi_resource.energy_data_manager.id
}

output "energy_data_manager_endpoint" {
  description = "Endpoint URL for the Azure Data Manager for Energy instance"
  value       = "https://${jsondecode(azapi_resource.energy_data_manager.output).properties.endpoint}"
  sensitive   = false
}

# Digital Twins Information
output "digital_twins_instance_name" {
  description = "Name of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.energy_analytics.name
}

output "digital_twins_instance_id" {
  description = "ID of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.energy_analytics.id
}

output "digital_twins_endpoint" {
  description = "Endpoint URL for the Azure Digital Twins instance"
  value       = "https://${azurerm_digital_twins_instance.energy_analytics.host_name}"
  sensitive   = false
}

output "digital_twins_identity_principal_id" {
  description = "Principal ID of the Digital Twins managed identity"
  value       = azurerm_digital_twins_instance.energy_analytics.identity[0].principal_id
}

# Time Series Insights Information
output "time_series_insights_environment_name" {
  description = "Name of the Time Series Insights environment"
  value       = azurerm_iot_time_series_insights_gen2_environment.energy_analytics.name
}

output "time_series_insights_environment_id" {
  description = "ID of the Time Series Insights environment"
  value       = azurerm_iot_time_series_insights_gen2_environment.energy_analytics.id
}

output "time_series_insights_data_access_fqdn" {
  description = "Data access FQDN for Time Series Insights"
  value       = azurerm_iot_time_series_insights_gen2_environment.energy_analytics.data_access_fqdn
}

# IoT Hub Information
output "iot_hub_name" {
  description = "Name of the IoT Hub for device data ingestion"
  value       = azurerm_iothub.energy_analytics.name
}

output "iot_hub_id" {
  description = "ID of the IoT Hub"
  value       = azurerm_iothub.energy_analytics.id
}

output "iot_hub_hostname" {
  description = "Hostname of the IoT Hub"
  value       = azurerm_iothub.energy_analytics.hostname
}

output "iot_hub_connection_string" {
  description = "Connection string for the IoT Hub (sensitive)"
  value       = azurerm_iothub.energy_analytics.shared_access_policy[0].connection_string
  sensitive   = true
}

# Cognitive Services Information
output "cognitive_services_account_name" {
  description = "Name of the Cognitive Services account"
  value       = azurerm_cognitive_account.energy_analytics.name
}

output "cognitive_services_account_id" {
  description = "ID of the Cognitive Services account"
  value       = azurerm_cognitive_account.energy_analytics.id
}

output "cognitive_services_endpoint" {
  description = "Endpoint URL for the Cognitive Services account"
  value       = azurerm_cognitive_account.energy_analytics.endpoint
}

output "cognitive_services_primary_access_key" {
  description = "Primary access key for Cognitive Services (sensitive)"
  value       = azurerm_cognitive_account.energy_analytics.primary_access_key
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for data storage"
  value       = azurerm_storage_account.energy_analytics.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.energy_analytics.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.energy_analytics.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.energy_analytics.primary_connection_string
  sensitive   = true
}

# Storage Container Information
output "storage_containers" {
  description = "Names of created storage containers"
  value = {
    analytics_config = azurerm_storage_container.analytics_config.name
    dtdl_models     = azurerm_storage_container.dtdl_models.name
    ml_artifacts    = azurerm_storage_container.ml_artifacts.name
    iot_data        = azurerm_storage_container.iot_data.name
  }
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App for data integration"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.energy_analytics[0].name : azurerm_windows_function_app.energy_analytics[0].name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.energy_analytics[0].id : azurerm_windows_function_app.energy_analytics[0].id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.energy_analytics[0].default_hostname : azurerm_windows_function_app.energy_analytics[0].default_hostname
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = var.function_app_os_type == "linux" ? azurerm_linux_function_app.energy_analytics[0].identity[0].principal_id : azurerm_windows_function_app.energy_analytics[0].identity[0].principal_id
}

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic for real-time alerting"
  value       = azurerm_eventgrid_topic.energy_analytics.name
}

output "event_grid_topic_id" {
  description = "ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.energy_analytics.id
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL for the Event Grid topic"
  value       = azurerm_eventgrid_topic.energy_analytics.endpoint
}

output "event_grid_topic_primary_access_key" {
  description = "Primary access key for the Event Grid topic (sensitive)"
  value       = azurerm_eventgrid_topic.energy_analytics.primary_access_key
  sensitive   = true
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.energy_analytics.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.energy_analytics.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.energy_analytics.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace (sensitive)"
  value       = azurerm_log_analytics_workspace.energy_analytics.primary_shared_key
  sensitive   = true
}

# Application Insights Information (conditional)
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.energy_analytics[0].name : null
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.energy_analytics[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.energy_analytics[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.energy_analytics[0].connection_string : null
  sensitive   = true
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for secret management"
  value       = azurerm_key_vault.energy_analytics.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.energy_analytics.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.energy_analytics.vault_uri
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.energy_analytics.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.energy_analytics.id
}

# Random Suffix for Reference
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Deployment Configuration Summary
output "deployment_summary" {
  description = "Summary of key deployment configuration"
  value = {
    environment                    = var.environment
    project_name                  = var.project_name
    location                      = var.location
    digital_twins_instance_name   = azurerm_digital_twins_instance.energy_analytics.name
    time_series_insights_sku      = var.time_series_insights_sku
    iot_hub_sku                   = var.iot_hub_sku
    cognitive_services_sku        = var.cognitive_services_sku
    function_app_os_type          = var.function_app_os_type
    function_app_runtime          = var.function_app_runtime
    enable_diagnostic_settings    = var.enable_diagnostic_settings
    enable_application_insights   = var.enable_application_insights
    create_sample_dtdl_models     = var.create_sample_dtdl_models
    create_sample_digital_twins   = var.create_sample_digital_twins
  }
}

# Connection Information for Applications
output "connection_information" {
  description = "Key connection information for applications and integrations"
  value = {
    digital_twins_endpoint           = "https://${azurerm_digital_twins_instance.energy_analytics.host_name}"
    cognitive_services_endpoint      = azurerm_cognitive_account.energy_analytics.endpoint
    storage_account_name            = azurerm_storage_account.energy_analytics.name
    event_grid_topic_endpoint       = azurerm_eventgrid_topic.energy_analytics.endpoint
    time_series_insights_environment = azurerm_iot_time_series_insights_gen2_environment.energy_analytics.name
    iot_hub_hostname                = azurerm_iothub.energy_analytics.hostname
    key_vault_uri                   = azurerm_key_vault.energy_analytics.vault_uri
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.energy_analytics.workspace_id
  }
  sensitive = false
}

# Sample Configuration Files
output "sample_configuration_files" {
  description = "Information about uploaded sample configuration files"
  value = {
    analytics_config = {
      container = azurerm_storage_container.analytics_config.name
      blob      = azurerm_storage_blob.analytics_config.name
      url       = azurerm_storage_blob.analytics_config.url
    }
    dashboard_config = {
      container = azurerm_storage_container.analytics_config.name
      blob      = azurerm_storage_blob.dashboard_config.name
      url       = azurerm_storage_blob.dashboard_config.url
    }
    dtdl_models = var.create_sample_dtdl_models ? {
      container = azurerm_storage_container.dtdl_models.name
      power_generator = {
        blob = azurerm_storage_blob.power_generator_model[0].name
        url  = azurerm_storage_blob.power_generator_model[0].url
      }
      grid_node = {
        blob = azurerm_storage_blob.grid_node_model[0].name
        url  = azurerm_storage_blob.grid_node_model[0].url
      }
    } : null
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps for completing the energy grid analytics setup"
  value = {
    instructions = [
      "1. Configure DTDL models in Digital Twins using the uploaded sample models",
      "2. Create sample digital twin instances representing your energy grid components",
      "3. Set up IoT device connections to start sending telemetry data",
      "4. Configure Event Grid subscriptions for real-time alerting",
      "5. Deploy Function App code for data processing and integration",
      "6. Set up Power BI or custom dashboards for visualization",
      "7. Configure AI models for predictive analytics using historical data",
      "8. Test the complete data flow from IoT devices to analytics outputs"
    ]
    important_notes = [
      "Azure Data Manager for Energy requires special provisioning - contact Azure support",
      "Digital Twins models must be created before digital twin instances",
      "IoT Hub connection strings are stored securely in Key Vault",
      "Monitor costs using Azure Cost Management + Billing",
      "Review and configure diagnostic settings for production use"
    ]
  }
}

# Resource URLs for Management
output "resource_urls" {
  description = "Direct URLs to key resources in Azure Portal"
  value = {
    resource_group     = "https://portal.azure.com/#@/resource${azurerm_resource_group.energy_analytics.id}"
    digital_twins      = "https://portal.azure.com/#@/resource${azurerm_digital_twins_instance.energy_analytics.id}"
    iot_hub           = "https://portal.azure.com/#@/resource${azurerm_iothub.energy_analytics.id}"
    cognitive_services = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.energy_analytics.id}"
    storage_account   = "https://portal.azure.com/#@/resource${azurerm_storage_account.energy_analytics.id}"
    function_app      = "https://portal.azure.com/#@/resource${var.function_app_os_type == "linux" ? azurerm_linux_function_app.energy_analytics[0].id : azurerm_windows_function_app.energy_analytics[0].id}"
    key_vault         = "https://portal.azure.com/#@/resource${azurerm_key_vault.energy_analytics.id}"
    log_analytics     = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.energy_analytics.id}"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs in the energy grid analytics platform"
  value = {
    recommendations = [
      "Use Azure Cost Management to monitor spending across all resources",
      "Consider using Azure Reserved Instances for predictable workloads",
      "Implement auto-scaling for Function Apps based on demand",
      "Use lifecycle management policies for blob storage to optimize costs",
      "Monitor Time Series Insights data retention to avoid unnecessary storage costs",
      "Review Cognitive Services usage and consider appropriate SKU sizing"
    ]
    monitoring_queries = [
      "Track IoT message volume to optimize IoT Hub tier",
      "Monitor Digital Twins API calls for cost optimization",
      "Analyze storage usage patterns for cost-effective storage tiers",
      "Review Function App execution statistics for right-sizing"
    ]
  }
}