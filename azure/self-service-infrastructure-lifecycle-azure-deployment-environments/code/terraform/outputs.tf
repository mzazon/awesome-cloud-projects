# =============================================================================
# Terraform Outputs
# Self-Service Infrastructure Lifecycle with Azure Deployment Environments
# =============================================================================

# =============================================================================
# DevCenter Outputs
# =============================================================================

output "devcenter_id" {
  description = "The ID of the Azure DevCenter"
  value       = azurerm_dev_center.main.id
}

output "devcenter_name" {
  description = "The name of the Azure DevCenter"
  value       = azurerm_dev_center.main.name
}

output "devcenter_location" {
  description = "The location of the Azure DevCenter"
  value       = azurerm_dev_center.main.location
}

output "devcenter_identity_principal_id" {
  description = "The principal ID of the DevCenter's managed identity"
  value       = azurerm_dev_center.main.identity[0].principal_id
}

output "devcenter_dev_center_uri" {
  description = "The URI of the DevCenter for API access"
  value       = azurerm_dev_center.main.dev_center_uri
}

# =============================================================================
# Project Outputs
# =============================================================================

output "project_id" {
  description = "The ID of the DevCenter project"
  value       = azurerm_dev_center_project.main.id
}

output "project_name" {
  description = "The name of the DevCenter project"
  value       = azurerm_dev_center_project.main.name
}

output "project_identity_principal_id" {
  description = "The principal ID of the project's managed identity"
  value       = azurerm_dev_center_project.main.identity[0].principal_id
}

output "project_dev_center_uri" {
  description = "The URI of the DevCenter for project access"
  value       = azurerm_dev_center_project.main.dev_center_uri
}

# =============================================================================
# Environment Type Outputs
# =============================================================================

output "environment_types" {
  description = "Map of environment types and their configurations"
  value = {
    for env_type in azurerm_dev_center_environment_type.environment_types : env_type.name => {
      id   = env_type.id
      name = env_type.name
      tags = env_type.tags
    }
  }
}

output "project_environment_types" {
  description = "Map of project environment types and their configurations"
  value = {
    for env_type in azurerm_dev_center_project_environment_type.project_environment_types : env_type.name => {
      id                     = env_type.id
      name                   = env_type.name
      deployment_target_id   = env_type.deployment_target_id
      identity_principal_id  = env_type.identity[0].principal_id
      creator_role_assignments = env_type.creator_role_assignment_roles
    }
  }
}

# =============================================================================
# Catalog Outputs
# =============================================================================

output "catalog_id" {
  description = "The ID of the DevCenter catalog"
  value       = azurerm_dev_center_catalog.main.id
}

output "catalog_name" {
  description = "The name of the DevCenter catalog"
  value       = azurerm_dev_center_catalog.main.name
}

# =============================================================================
# Storage Account Outputs
# =============================================================================

output "storage_account_id" {
  description = "The ID of the storage account"
  value       = azurerm_storage_account.templates.id
}

output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.templates.name
}

output "storage_account_primary_endpoint" {
  description = "The primary endpoint of the storage account"
  value       = azurerm_storage_account.templates.primary_blob_endpoint
}

output "templates_container_name" {
  description = "The name of the templates container"
  value       = azurerm_storage_container.templates.name
}

output "templates_container_url" {
  description = "The URL of the templates container"
  value       = "${azurerm_storage_account.templates.primary_blob_endpoint}${azurerm_storage_container.templates.name}"
}

# =============================================================================
# Resource Group Outputs
# =============================================================================

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.main.location
}

# =============================================================================
# Monitoring Outputs
# =============================================================================

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace (if enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace (if enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "application_insights_id" {
  description = "The ID of Application Insights (if enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].id : null
}

output "application_insights_name" {
  description = "The name of Application Insights (if enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key of Application Insights (if enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string of Application Insights (if enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# =============================================================================
# Cost Management Outputs
# =============================================================================

output "budget_id" {
  description = "The ID of the cost management budget"
  value       = azurerm_consumption_budget_resource_group.main.id
}

output "budget_name" {
  description = "The name of the cost management budget"
  value       = azurerm_consumption_budget_resource_group.main.name
}

output "budget_amount" {
  description = "The budget amount configured for cost management"
  value       = azurerm_consumption_budget_resource_group.main.amount
}

# =============================================================================
# Azure Developer CLI Integration Outputs
# =============================================================================

output "azd_configuration" {
  description = "Azure Developer CLI configuration information"
  value = {
    dev_center_name    = azurerm_dev_center.main.name
    dev_center_uri     = azurerm_dev_center.main.dev_center_uri
    project_name       = azurerm_dev_center_project.main.name
    subscription_id    = data.azurerm_client_config.current.subscription_id
    resource_group     = azurerm_resource_group.main.name
    location           = azurerm_resource_group.main.location
    environment_types  = [for env in var.environment_types : env.name]
    catalog_name       = azurerm_dev_center_catalog.main.name
  }
}

# =============================================================================
# Connection Information
# =============================================================================

output "deployment_environments_info" {
  description = "Information for connecting to Azure Deployment Environments"
  value = {
    dev_center_endpoint = "https://${azurerm_dev_center.main.name}-${azurerm_dev_center.main.location}.devcenter.azure.com/"
    project_name        = azurerm_dev_center_project.main.name
    subscription_id     = data.azurerm_client_config.current.subscription_id
    resource_group      = azurerm_resource_group.main.name
    available_environments = [for env in var.environment_types : env.name]
    catalog_templates = [for def in var.environment_definitions : def.name]
  }
}

# =============================================================================
# Azure CLI Commands
# =============================================================================

output "useful_commands" {
  description = "Useful Azure CLI commands for managing the deployment environments"
  value = {
    list_environments = "az devcenter dev environment list --project-name ${azurerm_dev_center_project.main.name} --endpoint https://${azurerm_dev_center.main.name}-${azurerm_dev_center.main.location}.devcenter.azure.com/"
    create_environment = "az devcenter dev environment create --project-name ${azurerm_dev_center_project.main.name} --endpoint https://${azurerm_dev_center.main.name}-${azurerm_dev_center.main.location}.devcenter.azure.com/ --environment-name <env-name> --environment-type <env-type> --catalog-name ${azurerm_dev_center_catalog.main.name} --environment-definition-name <def-name>"
    delete_environment = "az devcenter dev environment delete --project-name ${azurerm_dev_center_project.main.name} --endpoint https://${azurerm_dev_center.main.name}-${azurerm_dev_center.main.location}.devcenter.azure.com/ --environment-name <env-name>"
    azd_configuration = "azd config set platform.type devcenter"
  }
}

# =============================================================================
# Summary Information
# =============================================================================

output "deployment_summary" {
  description = "Summary of the deployed Azure Deployment Environments infrastructure"
  value = {
    dev_center_name           = azurerm_dev_center.main.name
    project_name              = azurerm_dev_center_project.main.name
    resource_group_name       = azurerm_resource_group.main.name
    location                  = azurerm_resource_group.main.location
    environment_types_count   = length(var.environment_types)
    catalog_name              = azurerm_dev_center_catalog.main.name
    storage_account_name      = azurerm_storage_account.templates.name
    monitoring_enabled        = var.enable_monitoring
    rbac_assignments_enabled  = var.enable_rbac_assignments
    cost_budget_amount        = var.cost_management_budget
    unique_suffix             = random_string.suffix.result
  }
}