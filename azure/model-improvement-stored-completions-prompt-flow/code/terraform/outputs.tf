# Outputs for Model Improvement Pipeline with Stored Completions and Prompt Flow
# This file defines the output values that will be displayed after successful deployment

#------------------------------------------------------------------------------
# RESOURCE GROUP INFORMATION
#------------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the created resource group containing all pipeline resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where all resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Full resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

#------------------------------------------------------------------------------
# AZURE OPENAI SERVICE INFORMATION
#------------------------------------------------------------------------------

output "openai_service_name" {
  description = "Name of the Azure OpenAI Service instance"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for Azure OpenAI Service API calls"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_service_id" {
  description = "Full resource ID of the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_custom_subdomain" {
  description = "Custom subdomain for Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.custom_subdomain_name
}

output "gpt4o_deployment_name" {
  description = "Name of the deployed GPT-4o model for conversation capture"
  value       = azurerm_cognitive_deployment.gpt4o.name
}

output "gpt4o_model_version" {
  description = "Version of the deployed GPT-4o model"
  value       = azurerm_cognitive_deployment.gpt4o.model[0].version
}

#------------------------------------------------------------------------------
# MACHINE LEARNING WORKSPACE INFORMATION
#------------------------------------------------------------------------------

output "ml_workspace_name" {
  description = "Name of the Azure Machine Learning workspace for Prompt Flow"
  value       = azurerm_machine_learning_workspace.main.name
}

output "ml_workspace_id" {
  description = "Full resource ID of the ML workspace"
  value       = azurerm_machine_learning_workspace.main.id
}

output "ml_workspace_discovery_url" {
  description = "Discovery URL for ML workspace access"
  value       = azurerm_machine_learning_workspace.main.discovery_url
}

output "ml_workspace_ml_flow_tracking_uri" {
  description = "MLflow tracking URI for experiment management"
  value       = azurerm_machine_learning_workspace.main.mlflow_tracking_uri
}

#------------------------------------------------------------------------------
# STORAGE ACCOUNT INFORMATION
#------------------------------------------------------------------------------

output "pipeline_storage_account_name" {
  description = "Name of the primary storage account for pipeline data"
  value       = azurerm_storage_account.pipeline_storage.name
}

output "pipeline_storage_primary_endpoint" {
  description = "Primary blob endpoint for pipeline storage account"
  value       = azurerm_storage_account.pipeline_storage.primary_blob_endpoint
}

output "ml_storage_account_name" {
  description = "Name of the ML workspace storage account"
  value       = azurerm_storage_account.ml_storage.name
}

output "storage_containers" {
  description = "Names of created storage containers for pipeline data organization"
  value = {
    conversations   = azurerm_storage_container.conversations.name
    insights       = azurerm_storage_container.insights.name
    flow_artifacts = azurerm_storage_container.flow_artifacts.name
  }
}

#------------------------------------------------------------------------------
# FUNCTION APP INFORMATION
#------------------------------------------------------------------------------

output "function_app_name" {
  description = "Name of the Azure Function App for pipeline automation"
  value       = azurerm_linux_function_app.pipeline_functions.name
}

output "function_app_hostname" {
  description = "Default hostname for the Function App"
  value       = azurerm_linux_function_app.pipeline_functions.default_hostname
}

output "function_app_principal_id" {
  description = "System-assigned managed identity principal ID for the Function App"
  value       = azurerm_linux_function_app.pipeline_functions.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "System-assigned managed identity tenant ID for the Function App"
  value       = azurerm_linux_function_app.pipeline_functions.identity[0].tenant_id
}

#------------------------------------------------------------------------------
# MONITORING AND LOGGING INFORMATION
#------------------------------------------------------------------------------

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for monitoring"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Full resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance for ML workspace monitoring"
  value       = azurerm_application_insights.ml_insights.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive output)"
  value       = azurerm_application_insights.ml_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive output)"
  value       = azurerm_application_insights.ml_insights.connection_string
  sensitive   = true
}

#------------------------------------------------------------------------------
# SECURITY AND ACCESS INFORMATION
#------------------------------------------------------------------------------

output "key_vault_name" {
  description = "Name of the Key Vault for ML workspace secrets"
  value       = azurerm_key_vault.ml_keyvault.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault for programmatic access"
  value       = azurerm_key_vault.ml_keyvault.vault_uri
}

output "container_registry_name" {
  description = "Name of the Azure Container Registry for ML workspace"
  value       = azurerm_container_registry.ml_acr.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Container Registry"
  value       = azurerm_container_registry.ml_acr.login_server
}

#------------------------------------------------------------------------------
# PIPELINE CONFIGURATION INFORMATION
#------------------------------------------------------------------------------

output "pipeline_configuration" {
  description = "Key configuration parameters for the model improvement pipeline"
  value = {
    analysis_frequency        = var.pipeline_analysis_frequency
    batch_size               = var.pipeline_batch_size
    quality_threshold        = var.pipeline_quality_threshold
    alert_quality_threshold  = var.pipeline_alert_quality_threshold
    openai_api_version      = var.openai_api_version
    gpt4o_capacity          = var.gpt4o_capacity
  }
}

#------------------------------------------------------------------------------
# CONNECTION INFORMATION FOR DEVELOPMENT
#------------------------------------------------------------------------------

output "development_connection_info" {
  description = "Connection information for development and testing (sensitive data marked)"
  value = {
    openai_endpoint           = azurerm_cognitive_account.openai.endpoint
    openai_deployment_name    = azurerm_cognitive_deployment.gpt4o.name
    ml_workspace_name         = azurerm_machine_learning_workspace.main.name
    resource_group_name       = azurerm_resource_group.main.name
    subscription_id           = data.azurerm_client_config.current.subscription_id
    storage_account_name      = azurerm_storage_account.pipeline_storage.name
    function_app_name         = azurerm_linux_function_app.pipeline_functions.name
    log_analytics_workspace   = azurerm_log_analytics_workspace.main.name
  }
}

#------------------------------------------------------------------------------
# COST TRACKING INFORMATION
#------------------------------------------------------------------------------

output "deployed_resources_count" {
  description = "Summary of deployed resources for cost tracking"
  value = {
    cognitive_services_accounts = 1
    machine_learning_workspaces = 1
    storage_accounts           = 2
    function_apps              = 1
    container_registries       = 1
    key_vaults                 = 1
    log_analytics_workspaces   = 1
    application_insights       = 1
    total_major_resources      = 9
  }
}

output "resource_tags" {
  description = "Tags applied to all resources for organization and cost allocation"
  value       = local.common_tags
}

#------------------------------------------------------------------------------
# NEXT STEPS INFORMATION
#------------------------------------------------------------------------------

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Configure Prompt Flow workflows in the ML workspace",
    "2. Deploy Function App code for pipeline automation",
    "3. Test stored completions with the OpenAI endpoint",
    "4. Set up monitoring alerts in Log Analytics",
    "5. Review and customize pipeline configuration parameters",
    "6. Configure authentication and access controls as needed",
    "7. Test the complete pipeline with sample conversation data"
  ]
}

#------------------------------------------------------------------------------
# IMPORTANT URLS AND ACCESS POINTS
#------------------------------------------------------------------------------

output "important_urls" {
  description = "Important URLs for accessing deployed services"
  value = {
    azure_portal_resource_group = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}"
    ml_studio_workspace        = "https://ml.azure.com/workspaces/${azurerm_machine_learning_workspace.main.name}/home?wsid=/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourcegroups/${azurerm_resource_group.main.name}/workspaces/${azurerm_machine_learning_workspace.main.name}"
    function_app_portal        = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Web/sites/${azurerm_linux_function_app.pipeline_functions.name}"
    openai_studio             = "https://oai.azure.com/"
    log_analytics_workspace   = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.OperationalInsights/workspaces/${azurerm_log_analytics_workspace.main.name}"
  }
}