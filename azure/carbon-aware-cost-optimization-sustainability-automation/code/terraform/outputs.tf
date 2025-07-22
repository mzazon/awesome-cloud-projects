# Output values for Azure Carbon-Aware Cost Optimization Solution
# These outputs provide important information for verification and integration

output "resource_group_name" {
  description = "Name of the resource group containing all carbon optimization resources"
  value       = azurerm_resource_group.carbon_optimization.name
}

output "resource_group_id" {
  description = "Resource ID of the carbon optimization resource group"
  value       = azurerm_resource_group.carbon_optimization.id
}

output "subscription_id" {
  description = "Azure subscription ID where resources are deployed"
  value       = data.azurerm_subscription.current.subscription_id
}

# Automation Account outputs
output "automation_account_name" {
  description = "Name of the Azure Automation Account for carbon optimization"
  value       = azurerm_automation_account.carbon_optimization.name
}

output "automation_account_id" {
  description = "Resource ID of the Azure Automation Account"
  value       = azurerm_automation_account.carbon_optimization.id
}

output "automation_account_managed_identity_principal_id" {
  description = "Principal ID of the Automation Account's managed identity"
  value       = azurerm_user_assigned_identity.carbon_optimization.principal_id
}

output "automation_account_managed_identity_client_id" {
  description = "Client ID of the Automation Account's managed identity"
  value       = azurerm_user_assigned_identity.carbon_optimization.client_id
}

# Key Vault outputs
output "key_vault_name" {
  description = "Name of the Key Vault storing carbon optimization configuration"
  value       = azurerm_key_vault.carbon_optimization.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.carbon_optimization.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault for accessing secrets"
  value       = azurerm_key_vault.carbon_optimization.vault_uri
}

# Configuration secrets (names only for security)
output "carbon_optimization_secrets" {
  description = "Names of Key Vault secrets containing carbon optimization configuration"
  value = {
    carbon_threshold_kg             = azurerm_key_vault_secret.carbon_threshold_kg.name
    cost_threshold_usd             = azurerm_key_vault_secret.cost_threshold_usd.name
    min_carbon_reduction_percent   = azurerm_key_vault_secret.min_carbon_reduction_percent.name
    cpu_utilization_threshold      = azurerm_key_vault_secret.cpu_utilization_threshold.name
  }
}

# Logic Apps outputs
output "logic_app_name" {
  description = "Name of the Logic App orchestrating carbon optimization workflows"
  value       = azurerm_logic_app_workflow.carbon_optimization.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.carbon_optimization.id
}

output "logic_app_managed_identity_principal_id" {
  description = "Principal ID of the Logic App's managed identity"
  value       = azurerm_user_assigned_identity.carbon_optimization.principal_id
}

# Log Analytics outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for carbon optimization monitoring"
  value       = azurerm_log_analytics_workspace.carbon_optimization.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.carbon_optimization.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (GUID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.carbon_optimization.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace access"
  value       = azurerm_log_analytics_workspace.carbon_optimization.primary_shared_key
  sensitive   = true
}

# Storage Account outputs
output "storage_account_name" {
  description = "Name of the storage account used by Logic Apps and automation workflows"
  value       = azurerm_storage_account.carbon_optimization.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.carbon_optimization.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.carbon_optimization.primary_blob_endpoint
}

# Runbook outputs
output "carbon_optimization_runbook_name" {
  description = "Name of the carbon optimization runbook"
  value       = azurerm_automation_runbook.carbon_optimization.name
}

output "carbon_optimization_runbook_id" {
  description = "Resource ID of the carbon optimization runbook"
  value       = azurerm_automation_runbook.carbon_optimization.id
}

# Schedule outputs
output "optimization_schedules" {
  description = "Information about carbon optimization schedules"
  value = {
    daily_schedule = {
      name        = azurerm_automation_schedule.daily_optimization.name
      frequency   = azurerm_automation_schedule.daily_optimization.frequency
      start_time  = azurerm_automation_schedule.daily_optimization.start_time
    }
    peak_schedule = {
      name        = azurerm_automation_schedule.peak_optimization.name
      frequency   = azurerm_automation_schedule.peak_optimization.frequency
      start_time  = azurerm_automation_schedule.peak_optimization.start_time
    }
  }
}

# Managed Identity outputs
output "user_assigned_identity_name" {
  description = "Name of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.carbon_optimization.name
}

output "user_assigned_identity_id" {
  description = "Resource ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.carbon_optimization.id
}

output "user_assigned_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.carbon_optimization.principal_id
}

output "user_assigned_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.carbon_optimization.client_id
}

# Configuration values (for reference)
output "carbon_optimization_configuration" {
  description = "Carbon optimization configuration values used in deployment"
  value = {
    carbon_threshold_kg             = var.carbon_threshold_kg
    cost_threshold_usd             = var.cost_threshold_usd
    min_carbon_reduction_percent   = var.min_carbon_reduction_percent
    cpu_utilization_threshold      = var.cpu_utilization_threshold
    optimization_schedule_time     = var.optimization_schedule_time
    peak_optimization_schedule_time = var.peak_optimization_schedule_time
    log_analytics_retention_days   = var.log_analytics_retention_days
  }
}

# Tags applied to resources
output "resource_tags" {
  description = "Common tags applied to all carbon optimization resources"
  value       = local.common_tags
}

# Azure Carbon Optimization API endpoints
output "carbon_optimization_api_endpoints" {
  description = "Azure Carbon Optimization API endpoints for manual testing"
  value = {
    recommendations_api = "https://management.azure.com/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.CarbonOptimization/carbonOptimizationRecommendations?api-version=2023-10-01-preview"
    carbon_usage_api   = "https://management.azure.com/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.CarbonOptimization/carbonUsage?api-version=2023-10-01-preview"
  }
}

# Deployment information
output "deployment_info" {
  description = "Information about the carbon optimization deployment"
  value = {
    location              = var.location
    environment           = var.environment
    project_name          = var.project_name
    random_suffix         = random_string.suffix.result
    tenant_id            = data.azurerm_client_config.current.tenant_id
    deployment_timestamp = timestamp()
  }
}

# Next steps and validation commands
output "validation_commands" {
  description = "Azure CLI commands to validate the carbon optimization deployment"
  value = {
    check_automation_account = "az automation account show --name ${azurerm_automation_account.carbon_optimization.name} --resource-group ${azurerm_resource_group.carbon_optimization.name}"
    check_key_vault         = "az keyvault show --name ${azurerm_key_vault.carbon_optimization.name}"
    check_logic_app         = "az logic workflow show --name ${azurerm_logic_app_workflow.carbon_optimization.name} --resource-group ${azurerm_resource_group.carbon_optimization.name}"
    test_carbon_api         = "az rest --method GET --url \"https://management.azure.com/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.CarbonOptimization/carbonOptimizationRecommendations?api-version=2023-10-01-preview\""
    trigger_logic_app       = "az logic workflow trigger run --name ${azurerm_logic_app_workflow.carbon_optimization.name} --resource-group ${azurerm_resource_group.carbon_optimization.name} --trigger-name Recurrence"
  }
}