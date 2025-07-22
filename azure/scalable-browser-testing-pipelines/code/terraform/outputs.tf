# Output values for Azure Playwright Testing with Azure DevOps Infrastructure
# This file defines all output values that will be displayed after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Azure Container Registry Outputs
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_username
}

output "container_registry_admin_password" {
  description = "Admin password for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

output "container_registry_id" {
  description = "ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

# Azure Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_id" {
  description = "ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for test artifacts"
  value       = azurerm_storage_account.test_artifacts.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.test_artifacts.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.test_artifacts.primary_access_key
  sensitive   = true
}

output "test_reports_container_name" {
  description = "Name of the test reports storage container"
  value       = azurerm_storage_container.test_reports.name
}

output "test_media_container_name" {
  description = "Name of the test media storage container"
  value       = azurerm_storage_container.test_media.name
}

# Azure DevOps Project Outputs
output "azuredevops_project_name" {
  description = "Name of the Azure DevOps project"
  value       = azuredevops_project.main.name
}

output "azuredevops_project_id" {
  description = "ID of the Azure DevOps project"
  value       = azuredevops_project.main.id
}

output "azuredevops_project_url" {
  description = "URL of the Azure DevOps project"
  value       = azuredevops_project.main.project_url
}

# Azure DevOps Repository Outputs
output "azuredevops_repository_name" {
  description = "Name of the Azure DevOps Git repository"
  value       = azuredevops_git_repository.main.name
}

output "azuredevops_repository_id" {
  description = "ID of the Azure DevOps Git repository"
  value       = azuredevops_git_repository.main.id
}

output "azuredevops_repository_url" {
  description = "URL of the Azure DevOps Git repository"
  value       = azuredevops_git_repository.main.web_url
}

output "azuredevops_repository_clone_url" {
  description = "Clone URL for the Azure DevOps Git repository"
  value       = azuredevops_git_repository.main.remote_url
}

# Azure DevOps Pipeline Outputs
output "azuredevops_pipeline_name" {
  description = "Name of the Azure DevOps build pipeline"
  value       = azuredevops_build_definition.main.name
}

output "azuredevops_pipeline_id" {
  description = "ID of the Azure DevOps build pipeline"
  value       = azuredevops_build_definition.main.id
}

output "azuredevops_pipeline_url" {
  description = "URL of the Azure DevOps build pipeline"
  value       = "https://dev.azure.com/${azuredevops_project.main.name}/_build?definitionId=${azuredevops_build_definition.main.id}"
}

# Service Connection Outputs
output "azure_service_connection_name" {
  description = "Name of the Azure service connection"
  value       = azuredevops_serviceendpoint_azurerm.main.service_endpoint_name
}

output "azure_service_connection_id" {
  description = "ID of the Azure service connection"
  value       = azuredevops_serviceendpoint_azurerm.main.id
}

output "acr_service_connection_name" {
  description = "Name of the Azure Container Registry service connection"
  value       = azuredevops_serviceendpoint_dockerregistry.acr.service_endpoint_name
}

output "acr_service_connection_id" {
  description = "ID of the Azure Container Registry service connection"
  value       = azuredevops_serviceendpoint_dockerregistry.acr.id
}

# Variable Group Outputs
output "pipeline_variable_group_name" {
  description = "Name of the pipeline variable group"
  value       = azuredevops_variable_group.pipeline_vars.name
}

output "pipeline_variable_group_id" {
  description = "ID of the pipeline variable group"
  value       = azuredevops_variable_group.pipeline_vars.id
}

# Dashboard Outputs
output "test_dashboard_name" {
  description = "Name of the test results dashboard"
  value       = azuredevops_dashboard.test_dashboard.name
}

output "test_dashboard_id" {
  description = "ID of the test results dashboard"
  value       = azuredevops_dashboard.test_dashboard.id
}

# Monitoring Outputs (conditional)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

output "application_insights_name" {
  description = "Name of the Application Insights instance (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Alert Group Outputs (conditional)
output "monitor_action_group_name" {
  description = "Name of the monitor action group for alerts (if monitoring enabled and email provided)"
  value       = var.enable_monitoring && var.notification_email != "" ? azurerm_monitor_action_group.test_alerts[0].name : null
}

output "monitor_action_group_id" {
  description = "ID of the monitor action group for alerts (if monitoring enabled and email provided)"
  value       = var.enable_monitoring && var.notification_email != "" ? azurerm_monitor_action_group.test_alerts[0].id : null
}

# Configuration Summary Outputs
output "playwright_configuration_summary" {
  description = "Summary of Playwright testing configuration"
  value = {
    browsers           = var.playwright_browsers
    node_version      = var.node_version
    environment       = var.environment
    monitoring_enabled = var.enable_monitoring
    notification_email = var.notification_email != "" ? var.notification_email : "Not configured"
  }
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group          = azurerm_resource_group.main.name
    container_registry      = azurerm_container_registry.main.name
    key_vault              = azurerm_key_vault.main.name
    storage_account        = azurerm_storage_account.test_artifacts.name
    devops_project         = azuredevops_project.main.name
    pipeline               = azuredevops_build_definition.main.name
    monitoring_enabled     = var.enable_monitoring
    location               = azurerm_resource_group.main.location
    environment           = var.environment
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps to complete the setup"
  value = {
    step_1 = "Clone the repository: git clone ${azuredevops_git_repository.main.remote_url}"
    step_2 = "Create the pipeline YAML file at: ${var.pipeline_yaml_path}"
    step_3 = "Add Playwright test files to the repository"
    step_4 = "Configure pipeline variables with actual values"
    step_5 = "Run the pipeline to execute tests"
    step_6 = "Monitor results in the Azure DevOps dashboard"
  }
}

# Security Notes
output "security_notes" {
  description = "Important security considerations"
  value = {
    note_1 = "Update service principal credentials in the Azure service connection"
    note_2 = "Review and configure appropriate Key Vault access policies"
    note_3 = "Ensure proper network security groups are configured if needed"
    note_4 = "Consider enabling Azure AD authentication for enhanced security"
    note_5 = "Regularly rotate container registry credentials"
  }
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    tip_1 = "Use Basic SKU for ACR in non-production environments"
    tip_2 = "Configure retention policies to automatically delete old artifacts"
    tip_3 = "Monitor storage usage and clean up unused test media"
    tip_4 = "Consider using spot instances for pipeline agents if available"
    tip_5 = "Review and optimize Log Analytics retention periods"
  }
}