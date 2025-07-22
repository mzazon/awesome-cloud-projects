# Output values for Azure AI Studio Prompt Flow and Container Apps infrastructure
# These outputs provide important information for accessing and using the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Azure AI Hub and Project Information
output "ai_hub_name" {
  description = "Name of the Azure AI Hub workspace"
  value       = azurerm_machine_learning_workspace.ai_hub.name
}

output "ai_hub_workspace_id" {
  description = "Workspace ID of the Azure AI Hub"
  value       = azurerm_machine_learning_workspace.ai_hub.workspace_id
}

output "ai_hub_discovery_url" {
  description = "Discovery URL for the Azure AI Hub"
  value       = azurerm_machine_learning_workspace.ai_hub.discovery_url
}

output "ai_project_name" {
  description = "Name of the Azure AI Project workspace"
  value       = azurerm_machine_learning_workspace.ai_project.name
}

output "ai_project_workspace_id" {
  description = "Workspace ID of the Azure AI Project"
  value       = azurerm_machine_learning_workspace.ai_project.workspace_id
}

# Azure OpenAI Service Information
output "openai_account_name" {
  description = "Name of the Azure OpenAI account"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_model_deployment_name" {
  description = "Name of the deployed OpenAI model"
  value       = azurerm_cognitive_deployment.openai_model.name
}

output "openai_primary_access_key" {
  description = "Primary access key for Azure OpenAI (sensitive)"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

# Container Registry Information
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the Container Registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "Admin password for the Container Registry (sensitive)"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

# Container Apps Information
output "container_app_environment_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_app_environment_id" {
  description = "Resource ID of the Container Apps environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_app_name" {
  description = "Name of the Container App"
  value       = azurerm_container_app.promptflow.name
}

output "container_app_fqdn" {
  description = "Fully qualified domain name of the Container App"
  value       = azurerm_container_app.promptflow.ingress[0].fqdn
}

output "container_app_url" {
  description = "HTTPS URL of the Container App"
  value       = "https://${azurerm_container_app.promptflow.ingress[0].fqdn}"
}

output "container_app_latest_revision_name" {
  description = "Name of the latest revision of the Container App"
  value       = azurerm_container_app.promptflow.latest_revision_name
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used by AI Hub"
  value       = azurerm_storage_account.ai_hub.name
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.ai_hub.primary_blob_endpoint
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

# Monitoring Information (conditional outputs based on monitoring enablement)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if monitoring is enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if monitoring is enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "application_insights_name" {
  description = "Name of the Application Insights instance (if monitoring is enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if monitoring is enabled, sensitive)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if monitoring is enabled, sensitive)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Managed Identity Information (conditional outputs based on managed identity enablement)
output "container_app_principal_id" {
  description = "Principal ID of the Container App's system-assigned managed identity (if enabled)"
  value       = var.enable_managed_identity ? azurerm_container_app.promptflow.identity[0].principal_id : null
}

output "container_app_tenant_id" {
  description = "Tenant ID of the Container App's system-assigned managed identity (if enabled)"
  value       = var.enable_managed_identity ? azurerm_container_app.promptflow.identity[0].tenant_id : null
}

# Quick Start Information
output "prompt_flow_api_endpoint" {
  description = "API endpoint for testing prompt flow (POST requests to /score)"
  value       = "https://${azurerm_container_app.promptflow.ingress[0].fqdn}/score"
}

output "azure_portal_links" {
  description = "Quick links to Azure Portal for key resources"
  value = {
    resource_group      = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    ai_hub             = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.MachineLearningServices/workspaces/${azurerm_machine_learning_workspace.ai_hub.name}/overview"
    container_app      = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.App/containerApps/${azurerm_container_app.promptflow.name}/overview"
    application_insights = var.enable_monitoring ? "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/microsoft.insights/components/${azurerm_application_insights.main[0].name}/overview" : null
  }
}

# Docker Commands for Container Build and Push
output "docker_commands" {
  description = "Docker commands for building and pushing prompt flow container"
  value = {
    login = "az acr login --name ${azurerm_container_registry.main.name}"
    build = "docker build -t promptflow-app:latest ."
    tag   = "docker tag promptflow-app:latest ${azurerm_container_registry.main.login_server}/promptflow-app:latest"
    push  = "docker push ${azurerm_container_registry.main.login_server}/promptflow-app:latest"
  }
}

# Environment Variables for Local Development
output "environment_variables" {
  description = "Environment variables for local development and testing"
  value = {
    AZURE_OPENAI_ENDPOINT     = azurerm_cognitive_account.openai.endpoint
    AZURE_OPENAI_DEPLOYMENT  = azurerm_cognitive_deployment.openai_model.name
    CONTAINER_REGISTRY_URL    = azurerm_container_registry.main.login_server
    RESOURCE_GROUP_NAME       = azurerm_resource_group.main.name
    LOCATION                  = azurerm_resource_group.main.location
  }
}

# Sensitive Environment Variables (separate output for security)
output "sensitive_environment_variables" {
  description = "Sensitive environment variables (use with caution)"
  value = {
    AZURE_OPENAI_API_KEY      = azurerm_cognitive_account.openai.primary_access_key
    ACR_USERNAME              = azurerm_container_registry.main.admin_username
    ACR_PASSWORD              = azurerm_container_registry.main.admin_password
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  }
  sensitive = true
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for deployed resources (approximate)"
  value = {
    container_apps_environment = "~$0 (pay-per-use)"
    container_app             = "~$0-50 (depends on usage and scaling)"
    container_registry_basic  = "~$5/month"
    azure_openai_s0          = "~$0 (pay-per-token)"
    storage_account_standard = "~$1-5/month (depends on usage)"
    log_analytics_workspace  = var.enable_monitoring ? "~$2-10/month (depends on ingestion)" : "Not deployed"
    application_insights     = var.enable_monitoring ? "~$0-5/month (depends on usage)" : "Not deployed"
    total_estimated_minimum  = "~$8-75/month (highly variable based on usage)"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    test_prompt_flow = "curl -X POST '${azurerm_container_app.promptflow.ingress[0].fqdn}/score' -H 'Content-Type: application/json' -d '{\"question\": \"What is Azure Container Apps?\"}'"
    check_app_logs   = "az containerapp logs show --name ${azurerm_container_app.promptflow.name} --resource-group ${azurerm_resource_group.main.name}"
    check_app_status = "az containerapp show --name ${azurerm_container_app.promptflow.name} --resource-group ${azurerm_resource_group.main.name} --query 'properties.provisioningState'"
  }
}