# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the created storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key of the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Connection string of the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_containers" {
  description = "Names of the created storage containers"
  value = {
    environmental_data = azurerm_storage_container.environmental_data.name
    processed_data     = azurerm_storage_container.processed_data.name
    archive_data       = azurerm_storage_container.archive_data.name
  }
}

# Azure Data Factory Outputs
output "data_factory_name" {
  description = "Name of the created Data Factory"
  value       = azurerm_data_factory.main.name
}

output "data_factory_id" {
  description = "ID of the created Data Factory"
  value       = azurerm_data_factory.main.id
}

output "data_factory_identity" {
  description = "Managed identity of the Data Factory"
  value = {
    principal_id = azurerm_data_factory.main.identity[0].principal_id
    tenant_id    = azurerm_data_factory.main.identity[0].tenant_id
  }
}

output "data_factory_pipeline_name" {
  description = "Name of the environmental data pipeline"
  value       = azurerm_data_factory_pipeline.environmental_pipeline.name
}

output "data_factory_trigger_name" {
  description = "Name of the pipeline trigger"
  value       = azurerm_data_factory_trigger_schedule.daily_trigger.name
}

output "data_factory_linked_services" {
  description = "Names of the created linked services"
  value = {
    storage_service  = azurerm_data_factory_linked_service_azure_blob_storage.main.name
    function_service = azurerm_data_factory_linked_service_azure_function.main.name
  }
}

output "data_factory_datasets" {
  description = "Names of the created datasets"
  value = {
    environmental_data = azurerm_data_factory_dataset_delimited_text.environmental_data.name
    processed_data     = azurerm_data_factory_dataset_delimited_text.processed_data.name
  }
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the created Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the created Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_identity" {
  description = "Managed identity of the Function App"
  value = {
    principal_id = azurerm_linux_function_app.main.identity[0].principal_id
    tenant_id    = azurerm_linux_function_app.main.identity[0].tenant_id
  }
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.name}.azurewebsites.net"
}

output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the created Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the created Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the created Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string of Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Monitoring Alerts Outputs
output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.main[0].name : null
}

output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.main[0].id : null
}

output "pipeline_failure_alert_name" {
  description = "Name of the pipeline failure alert"
  value       = var.enable_monitoring ? azurerm_monitor_metric_alert.pipeline_failures[0].name : null
}

output "processing_delay_alert_name" {
  description = "Name of the processing delay alert"
  value       = var.enable_monitoring ? azurerm_monitor_metric_alert.processing_delays[0].name : null
}

# Cost Management Outputs
output "budget_name" {
  description = "Name of the cost management budget"
  value       = var.enable_cost_alerts ? azurerm_consumption_budget_resource_group.main[0].name : null
}

output "budget_amount" {
  description = "Amount of the cost management budget"
  value       = var.enable_cost_alerts ? var.monthly_budget_amount : null
}

# Access Information
output "access_instructions" {
  description = "Instructions for accessing the deployed resources"
  value = {
    data_factory_studio_url = "https://adf.azure.com/en-us/home?factory=%2Fsubscriptions%2F${data.azurerm_client_config.current.subscription_id}%2FresourceGroups%2F${azurerm_resource_group.main.name}%2Fproviders%2FMicrosoft.DataFactory%2Ffactories%2F${azurerm_data_factory.main.name}"
    storage_account_url     = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_account.main.id}/overview"
    function_app_url        = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_linux_function_app.main.id}/overview"
    key_vault_url          = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.main.id}/overview"
    log_analytics_url      = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.main.id}/overview"
    application_insights_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.main.id}/overview"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    managed_identity_enabled = true
    key_vault_enabled       = true
    private_endpoints       = var.enable_private_endpoints
    https_only             = true
    min_tls_version        = "1.2"
    network_restrictions   = length(var.allowed_ip_ranges) > 0 ? var.allowed_ip_ranges : ["All IP addresses allowed"]
  }
}

# Data Pipeline Configuration
output "pipeline_configuration" {
  description = "Data pipeline configuration details"
  value = {
    schedule_frequency = var.pipeline_schedule_frequency
    schedule_interval  = var.pipeline_schedule_interval
    start_time        = var.pipeline_schedule_start_time
    data_retention_days = var.data_retention_days
    monitoring_enabled = var.enable_monitoring
    diagnostic_settings = var.enable_diagnostic_settings
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = merge(var.tags, var.additional_tags)
}

# Random Suffix for Reference
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group          = azurerm_resource_group.main.name
    data_factory           = azurerm_data_factory.main.name
    storage_account        = azurerm_storage_account.main.name
    function_app           = azurerm_linux_function_app.main.name
    key_vault             = azurerm_key_vault.main.name
    log_analytics         = azurerm_log_analytics_workspace.main.name
    application_insights  = azurerm_application_insights.main.name
    pipeline_name         = azurerm_data_factory_pipeline.environmental_pipeline.name
    trigger_name          = azurerm_data_factory_trigger_schedule.daily_trigger.name
    monitoring_enabled    = var.enable_monitoring
    cost_alerts_enabled   = var.enable_cost_alerts
    total_containers      = 3
    total_datasets        = 2
    total_linked_services = 2
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload sample environmental data to the '${azurerm_storage_container.environmental_data.name}' container",
    "2. Deploy Function App code for data transformation to '${azurerm_linux_function_app.main.name}'",
    "3. Configure additional data sources in Data Factory Studio",
    "4. Set up custom alerts and dashboards in Azure Monitor",
    "5. Review and adjust pipeline schedule: ${var.pipeline_schedule_frequency} every ${var.pipeline_schedule_interval} at ${var.pipeline_schedule_start_time}",
    "6. Configure Azure Sustainability Manager integration for carbon tracking",
    "7. Test the complete pipeline end-to-end with sample data",
    "8. Set up additional notification channels in action group '${var.enable_monitoring ? azurerm_monitor_action_group.main[0].name : "N/A"}'",
    "9. Review cost optimization recommendations in Azure Advisor",
    "10. Implement additional security measures based on organizational requirements"
  ]
}