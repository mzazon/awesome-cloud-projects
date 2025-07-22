# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Azure AI Foundry Hub Information
output "ai_foundry_hub_name" {
  description = "Name of the Azure AI Foundry Hub (Machine Learning Workspace)"
  value       = azurerm_machine_learning_workspace.ai_foundry_hub.name
}

output "ai_foundry_hub_id" {
  description = "ID of the Azure AI Foundry Hub"
  value       = azurerm_machine_learning_workspace.ai_foundry_hub.id
}

output "ai_foundry_hub_workspace_id" {
  description = "Workspace ID of the Azure AI Foundry Hub"
  value       = azurerm_machine_learning_workspace.ai_foundry_hub.workspace_id
}

# Azure Data Factory Information
output "data_factory_name" {
  description = "Name of the Azure Data Factory instance"
  value       = azurerm_data_factory.main.name
}

output "data_factory_id" {
  description = "ID of the Azure Data Factory instance"
  value       = azurerm_data_factory.main.id
}

output "data_factory_identity_principal_id" {
  description = "Principal ID of the Data Factory managed identity"
  value       = var.data_factory_managed_identity ? azurerm_data_factory.main.identity[0].principal_id : null
}

output "data_factory_identity_tenant_id" {
  description = "Tenant ID of the Data Factory managed identity"
  value       = var.data_factory_managed_identity ? azurerm_data_factory.main.identity[0].tenant_id : null
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
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

output "storage_containers" {
  description = "List of created storage containers"
  value = {
    data_source     = azurerm_storage_container.data_source.name
    data_sink       = azurerm_storage_container.data_sink.name
    agent_artifacts = azurerm_storage_container.agent_artifacts.name
    pipeline_logs   = azurerm_storage_container.pipeline_logs.name
  }
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.pipeline_events.name
}

output "event_grid_topic_id" {
  description = "ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.pipeline_events.id
}

output "event_grid_topic_endpoint" {
  description = "Endpoint of the Event Grid topic"
  value       = azurerm_eventgrid_topic.pipeline_events.endpoint
}

output "event_grid_topic_primary_access_key" {
  description = "Primary access key of the Event Grid topic"
  value       = azurerm_eventgrid_topic.pipeline_events.primary_access_key
  sensitive   = true
}

output "event_grid_system_topic_name" {
  description = "Name of the Data Factory Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.data_factory.name
}

output "event_grid_system_topic_id" {
  description = "ID of the Data Factory Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.data_factory.id
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Cognitive Services Information
output "cognitive_services_name" {
  description = "Name of the Cognitive Services account"
  value       = azurerm_cognitive_account.main.name
}

output "cognitive_services_id" {
  description = "ID of the Cognitive Services account"
  value       = azurerm_cognitive_account.main.id
}

output "cognitive_services_endpoint" {
  description = "Endpoint of the Cognitive Services account"
  value       = azurerm_cognitive_account.main.endpoint
}

output "cognitive_services_primary_access_key" {
  description = "Primary access key of the Cognitive Services account"
  value       = azurerm_cognitive_account.main.primary_access_key
  sensitive   = true
}

# Function App Information (Agent Processor)
output "agent_processor_function_app_name" {
  description = "Name of the agent processor function app"
  value       = azurerm_linux_function_app.agent_processor.name
}

output "agent_processor_function_app_id" {
  description = "ID of the agent processor function app"
  value       = azurerm_linux_function_app.agent_processor.id
}

output "agent_processor_function_app_hostname" {
  description = "Default hostname of the agent processor function app"
  value       = azurerm_linux_function_app.agent_processor.default_hostname
}

output "agent_processor_identity_principal_id" {
  description = "Principal ID of the agent processor function app managed identity"
  value       = azurerm_linux_function_app.agent_processor.identity[0].principal_id
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of the Application Insights instance"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string of the Application Insights instance"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Monitoring Information
output "monitor_action_group_name" {
  description = "Name of the Azure Monitor Action Group"
  value       = azurerm_monitor_action_group.agent_alerts.name
}

output "monitor_action_group_id" {
  description = "ID of the Azure Monitor Action Group"
  value       = azurerm_monitor_action_group.agent_alerts.id
}

output "agent_failure_alert_id" {
  description = "ID of the agent failure alert rule"
  value       = azurerm_monitor_metric_alert.agent_failures.id
}

output "pipeline_failure_alert_id" {
  description = "ID of the pipeline failure alert rule"
  value       = azurerm_monitor_metric_alert.pipeline_failures.id
}

# Data Factory Pipeline Information
output "sample_pipeline_name" {
  description = "Name of the sample Data Factory pipeline"
  value       = azurerm_data_factory_pipeline.sample.name
}

output "sample_pipeline_id" {
  description = "ID of the sample Data Factory pipeline"
  value       = azurerm_data_factory_pipeline.sample.id
}

# Agent Configuration Information
output "agent_configurations" {
  description = "Configuration details for the AI agents"
  value = {
    for key, config in var.agent_configurations : key => {
      name         = config.name
      description  = config.description
      model_type   = config.model_type
      schedule     = config.schedule
      priority     = config.priority
      capabilities = config.capabilities
    }
  }
}

# Environment Information
output "environment_info" {
  description = "Environment and deployment information"
  value = {
    environment           = var.environment
    project_name         = var.project_name
    deployment_timestamp = timestamp()
    resource_suffix      = local.suffix
    terraform_version    = "~> 1.0"
    azurerm_version      = "~> 3.0"
  }
}

# Connection Strings and Endpoints
output "connection_endpoints" {
  description = "Key connection endpoints for the intelligent pipeline system"
  value = {
    data_factory_endpoint       = "https://${azurerm_data_factory.main.name}.azuredataservices.com"
    event_grid_endpoint         = azurerm_eventgrid_topic.pipeline_events.endpoint
    function_app_endpoint       = "https://${azurerm_linux_function_app.agent_processor.default_hostname}"
    log_analytics_portal_url    = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.main.id}/overview"
    application_insights_portal_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.main.id}/overview"
    key_vault_portal_url        = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.main.id}/overview"
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Next steps for completing the intelligent pipeline setup"
  value = {
    step_1 = "Upload sample data to the '${azurerm_storage_container.data_source.name}' container in storage account '${azurerm_storage_account.main.name}'"
    step_2 = "Deploy agent code to the Function App '${azurerm_linux_function_app.agent_processor.name}'"
    step_3 = "Configure AI agent logic in the AI Foundry Hub '${azurerm_machine_learning_workspace.ai_foundry_hub.name}'"
    step_4 = "Test the pipeline by running '${azurerm_data_factory_pipeline.sample.name}' in Data Factory"
    step_5 = "Monitor agent activities through Log Analytics workspace '${azurerm_log_analytics_workspace.main.name}'"
    step_6 = "Review monitoring dashboard and alerts in Azure Monitor"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    managed_identities_enabled = var.data_factory_managed_identity
    rbac_enabled               = true
    key_vault_rbac_enabled     = true
    storage_https_only         = true
    storage_min_tls_version    = "TLS1_2"
    key_vault_soft_delete_days = var.key_vault_soft_delete_retention_days
    diagnostic_settings_enabled = var.enable_diagnostic_settings
  }
}

# Cost Management Information
output "cost_management_info" {
  description = "Cost management and optimization information"
  value = {
    cost_optimization_enabled = var.enable_cost_optimization
    auto_shutdown_enabled     = var.auto_shutdown_enabled
    auto_shutdown_time        = var.auto_shutdown_time
    storage_tier              = var.storage_account_tier
    storage_replication       = var.storage_replication_type
    log_analytics_sku         = var.log_analytics_sku
    log_retention_days        = var.log_analytics_retention_in_days
    function_app_plan         = "Consumption (Y1)"
  }
}