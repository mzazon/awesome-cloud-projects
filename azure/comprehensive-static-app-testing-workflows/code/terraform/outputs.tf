# Output values for Azure CI/CD Testing Workflow Infrastructure
# These outputs provide essential information for integration and verification

# Resource Group Information
output "resource_group_name" {
  description = "The name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Static Web App Information
output "static_web_app_name" {
  description = "The name of the Azure Static Web App"
  value       = azurerm_static_web_app.main.name
}

output "static_web_app_url" {
  description = "The URL of the Azure Static Web App"
  value       = "https://${azurerm_static_web_app.main.default_host_name}"
}

output "static_web_app_default_hostname" {
  description = "The default hostname of the Azure Static Web App"
  value       = azurerm_static_web_app.main.default_host_name
}

output "static_web_app_deployment_token" {
  description = "The deployment token for the Azure Static Web App (sensitive)"
  value       = azurerm_static_web_app.main.api_key
  sensitive   = true
}

# Container Registry Information
output "container_registry_name" {
  description = "The name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "The login server of the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "The admin username for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "The admin password for the Azure Container Registry (sensitive)"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

# Container Apps Environment Information
output "container_apps_environment_name" {
  description = "The name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_apps_environment_id" {
  description = "The ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_apps_environment_default_domain" {
  description = "The default domain of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.default_domain
}

# Container Apps Jobs Information
output "integration_test_job_name" {
  description = "The name of the integration test Container Apps Job"
  value       = azurerm_container_app_job.integration_test.name
}

output "integration_test_job_id" {
  description = "The ID of the integration test Container Apps Job"
  value       = azurerm_container_app_job.integration_test.id
}

output "load_test_job_name" {
  description = "The name of the load test Container Apps Job"
  value       = var.enable_load_testing ? azurerm_container_app_job.load_test[0].name : null
}

output "load_test_job_id" {
  description = "The ID of the load test Container Apps Job"
  value       = var.enable_load_testing ? azurerm_container_app_job.load_test[0].id : null
}

output "ui_test_job_name" {
  description = "The name of the UI test Container Apps Job"
  value       = azurerm_container_app_job.ui_test.name
}

output "ui_test_job_id" {
  description = "The ID of the UI test Container Apps Job"
  value       = azurerm_container_app_job.ui_test.id
}

# Load Testing Information
output "load_test_resource_name" {
  description = "The name of the Azure Load Testing resource"
  value       = var.enable_load_testing ? azurerm_load_test.main[0].name : null
}

output "load_test_resource_id" {
  description = "The ID of the Azure Load Testing resource"
  value       = var.enable_load_testing ? azurerm_load_test.main[0].id : null
}

output "load_test_data_plane_uri" {
  description = "The data plane URI of the Azure Load Testing resource"
  value       = var.enable_load_testing ? azurerm_load_test.main[0].dataplane_uri : null
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "The customer ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "application_insights_name" {
  description = "The name of the Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_id" {
  description = "The ID of the Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key of the Application Insights instance (sensitive)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string of the Application Insights instance (sensitive)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# GitHub Actions Integration Information
output "github_actions_service_principal_client_id" {
  description = "The client ID of the GitHub Actions service principal"
  value       = var.enable_github_actions_integration ? azuread_service_principal.github_actions[0].client_id : null
}

output "github_actions_service_principal_object_id" {
  description = "The object ID of the GitHub Actions service principal"
  value       = var.enable_github_actions_integration ? azuread_service_principal.github_actions[0].object_id : null
}

output "github_actions_service_principal_password" {
  description = "The password of the GitHub Actions service principal (sensitive)"
  value       = var.enable_github_actions_integration ? azuread_service_principal_password.github_actions[0].value : null
  sensitive   = true
}

# GitHub Actions Secrets Configuration
output "github_actions_azure_credentials" {
  description = "The Azure credentials JSON for GitHub Actions (sensitive)"
  value = var.enable_github_actions_integration ? jsonencode({
    clientId       = azuread_service_principal.github_actions[0].client_id
    clientSecret   = azuread_service_principal_password.github_actions[0].value
    subscriptionId = data.azurerm_client_config.current.subscription_id
    tenantId       = data.azurerm_client_config.current.tenant_id
  }) : null
  sensitive = true
}

# Container Apps Jobs Start Commands
output "integration_test_start_command" {
  description = "Azure CLI command to start the integration test job"
  value = join(" ", [
    "az containerapp job start",
    "--resource-group ${azurerm_resource_group.main.name}",
    "--name ${azurerm_container_app_job.integration_test.name}"
  ])
}

output "load_test_start_command" {
  description = "Azure CLI command to start the load test job"
  value = var.enable_load_testing ? join(" ", [
    "az containerapp job start",
    "--resource-group ${azurerm_resource_group.main.name}",
    "--name ${azurerm_container_app_job.load_test[0].name}"
  ]) : null
}

output "ui_test_start_command" {
  description = "Azure CLI command to start the UI test job"
  value = join(" ", [
    "az containerapp job start",
    "--resource-group ${azurerm_resource_group.main.name}",
    "--name ${azurerm_container_app_job.ui_test.name}"
  ])
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    check_static_web_app = "az staticwebapp show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_static_web_app.main.name} --query 'provisioningState'"
    check_container_apps_env = "az containerapp env show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_container_app_environment.main.name} --query 'provisioningState'"
    check_container_registry = "az acr show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_container_registry.main.name} --query 'provisioningState'"
    test_web_app_url = "curl -I https://${azurerm_static_web_app.main.default_host_name}"
    list_container_jobs = "az containerapp job list --resource-group ${azurerm_resource_group.main.name} --output table"
  }
}

# Summary Information
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    resource_group      = azurerm_resource_group.main.name
    location           = azurerm_resource_group.main.location
    static_web_app_url = "https://${azurerm_static_web_app.main.default_host_name}"
    container_registry = azurerm_container_registry.main.login_server
    monitoring_enabled = var.enable_monitoring
    load_testing_enabled = var.enable_load_testing
    github_integration_enabled = var.enable_github_actions_integration
    total_container_jobs = 3
    environment        = var.environment
    project_name       = var.project_name
  }
}