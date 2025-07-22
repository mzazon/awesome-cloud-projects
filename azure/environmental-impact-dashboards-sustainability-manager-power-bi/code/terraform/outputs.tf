# =============================================================================
# OUTPUTS FOR AZURE SUSTAINABILITY MANAGER AND POWER BI INFRASTRUCTURE
# =============================================================================
# These outputs provide essential information for connecting to and managing
# the environmental impact dashboard solution components.

# =============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# =============================================================================

output "resource_group_name" {
  description = "Name of the resource group containing all sustainability resources"
  value       = azurerm_resource_group.sustainability.name
}

output "resource_group_id" {
  description = "ID of the resource group containing all sustainability resources"
  value       = azurerm_resource_group.sustainability.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.sustainability.location
}

# =============================================================================
# STORAGE AND DATA OUTPUTS
# =============================================================================

output "storage_account_name" {
  description = "Name of the storage account for sustainability data"
  value       = azurerm_storage_account.sustainability_data.name
}

output "storage_account_id" {
  description = "ID of the storage account for sustainability data"
  value       = azurerm_storage_account.sustainability_data.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob storage endpoint for sustainability data"
  value       = azurerm_storage_account.sustainability_data.primary_blob_endpoint
}

output "storage_containers" {
  description = "Names of storage containers for different data types"
  value = {
    sustainability_data = azurerm_storage_container.sustainability_data.name
    emissions_data     = azurerm_storage_container.emissions_data.name
    powerbi_data       = azurerm_storage_container.powerbi_data.name
  }
}

# =============================================================================
# DATA PROCESSING OUTPUTS
# =============================================================================

output "data_factory_name" {
  description = "Name of the Data Factory for sustainability data processing"
  value       = azurerm_data_factory.sustainability.name
}

output "data_factory_id" {
  description = "ID of the Data Factory for sustainability data processing"
  value       = azurerm_data_factory.sustainability.id
}

output "data_factory_identity_principal_id" {
  description = "Principal ID of the Data Factory's managed identity"
  value       = azurerm_data_factory.sustainability.identity[0].principal_id
}

output "function_app_name" {
  description = "Name of the Function App for emissions calculations"
  value       = azurerm_linux_function_app.emissions_calculator.name
}

output "function_app_id" {
  description = "ID of the Function App for emissions calculations"
  value       = azurerm_linux_function_app.emissions_calculator.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.emissions_calculator.default_hostname
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.emissions_calculator.identity[0].principal_id
}

# =============================================================================
# MONITORING AND LOGGING OUTPUTS
# =============================================================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.sustainability.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.sustainability.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.sustainability.workspace_id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.sustainability.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.sustainability.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.sustainability.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.sustainability.connection_string
  sensitive   = true
}

# =============================================================================
# SECURITY OUTPUTS
# =============================================================================

output "key_vault_name" {
  description = "Name of the Key Vault for sustainability secrets"
  value       = azurerm_key_vault.sustainability.name
}

output "key_vault_id" {
  description = "ID of the Key Vault for sustainability secrets"
  value       = azurerm_key_vault.sustainability.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault for sustainability secrets"
  value       = azurerm_key_vault.sustainability.vault_uri
}

# =============================================================================
# AUTOMATION OUTPUTS
# =============================================================================

output "logic_app_name" {
  description = "Name of the Logic App for sustainability automation"
  value       = azurerm_logic_app_workflow.sustainability_automation.name
}

output "logic_app_id" {
  description = "ID of the Logic App for sustainability automation"
  value       = azurerm_logic_app_workflow.sustainability_automation.id
}

output "logic_app_identity_principal_id" {
  description = "Principal ID of the Logic App's managed identity"
  value       = azurerm_logic_app_workflow.sustainability_automation.identity[0].principal_id
}

# =============================================================================
# POWER BI INTEGRATION OUTPUTS
# =============================================================================

output "power_bi_workspace_integration" {
  description = "Information needed for Power BI workspace integration"
  value = {
    storage_account_name = azurerm_storage_account.sustainability_data.name
    key_vault_name      = azurerm_key_vault.sustainability.name
    data_factory_name   = azurerm_data_factory.sustainability.name
    function_app_name   = azurerm_linux_function_app.emissions_calculator.name
  }
}

# =============================================================================
# DEPLOYMENT INFORMATION
# =============================================================================

output "deployment_info" {
  description = "Important deployment information and next steps"
  value = {
    resource_group     = azurerm_resource_group.sustainability.name
    location          = azurerm_resource_group.sustainability.location
    storage_account   = azurerm_storage_account.sustainability_data.name
    key_vault         = azurerm_key_vault.sustainability.name
    function_app      = azurerm_linux_function_app.emissions_calculator.name
    data_factory      = azurerm_data_factory.sustainability.name
    logic_app         = azurerm_logic_app_workflow.sustainability_automation.name
    app_insights      = azurerm_application_insights.sustainability.name
    
    next_steps = [
      "Configure Power BI workspace and datasets manually",
      "Deploy Function App code for emissions calculations",
      "Configure Data Factory pipelines for data ingestion",
      "Set up Logic App workflows for automation",
      "Configure monitoring alerts and notifications"
    ]
  }
}

# =============================================================================
# CONFIGURATION SUMMARY
# =============================================================================

output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    environment                = var.environment
    storage_tier              = var.storage_account_tier
    storage_replication       = var.storage_replication_type
    function_runtime          = var.function_app_runtime
    function_runtime_version  = var.function_app_runtime_version
    emissions_method          = var.emissions_calculation_method
    emissions_source          = var.emissions_factor_source
    sustainability_scopes     = var.sustainability_scopes
    monitoring_enabled        = var.enable_monitoring
    public_access_enabled     = var.enable_public_access
    retention_days           = var.retention_days
  }
}