# Outputs for Azure Cost Governance with Resource Graph and Power BI
# This file defines all output values from the cost governance solution

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all cost governance resources"
  value       = azurerm_resource_group.cost_governance.name
}

output "resource_group_location" {
  description = "Azure region where the resource group is located"
  value       = azurerm_resource_group.cost_governance.location
}

output "resource_group_id" {
  description = "Resource ID of the cost governance resource group"
  value       = azurerm_resource_group.cost_governance.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for cost governance data"
  value       = azurerm_storage_account.cost_governance.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.cost_governance.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.cost_governance.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.cost_governance.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.cost_governance.primary_connection_string
  sensitive   = true
}

# Storage Container Information
output "storage_containers" {
  description = "List of storage containers created for cost governance data"
  value = {
    resource_graph_data = azurerm_storage_container.resource_graph_data.name
    powerbi_datasets    = azurerm_storage_container.powerbi_datasets.name
    cost_reports        = azurerm_storage_container.cost_reports.name
  }
}

output "powerbi_data_source_url" {
  description = "URL for Power BI data source connection"
  value       = "${azurerm_storage_account.cost_governance.primary_blob_endpoint}${azurerm_storage_container.powerbi_datasets.name}"
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for secure configuration storage"
  value       = azurerm_key_vault.cost_governance.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.cost_governance.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.cost_governance.vault_uri
}

output "key_vault_secrets" {
  description = "List of secrets stored in the Key Vault"
  value = {
    cost_threshold_monthly = azurerm_key_vault_secret.cost_threshold_monthly.name
    cost_threshold_daily   = azurerm_key_vault_secret.cost_threshold_daily.name
  }
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App for cost monitoring automation"
  value       = azurerm_logic_app_workflow.cost_monitoring.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App"
  value       = azurerm_logic_app_workflow.cost_monitoring.id
}

output "logic_app_identity_principal_id" {
  description = "Principal ID of the Logic App's managed identity"
  value       = azurerm_logic_app_workflow.cost_monitoring.identity[0].principal_id
}

output "logic_app_identity_tenant_id" {
  description = "Tenant ID of the Logic App's managed identity"
  value       = azurerm_logic_app_workflow.cost_monitoring.identity[0].tenant_id
}

# Action Group Information
output "action_group_name" {
  description = "Name of the action group for cost alerts"
  value       = azurerm_monitor_action_group.cost_alerts.name
}

output "action_group_id" {
  description = "Resource ID of the action group"
  value       = azurerm_monitor_action_group.cost_alerts.id
}

output "action_group_short_name" {
  description = "Short name of the action group"
  value       = azurerm_monitor_action_group.cost_alerts.short_name
}

# Budget Information
output "budget_name" {
  description = "Name of the consumption budget"
  value       = azurerm_consumption_budget_subscription.monthly_cost_governance.name
}

output "budget_id" {
  description = "Resource ID of the consumption budget"
  value       = azurerm_consumption_budget_subscription.monthly_cost_governance.id
}

output "budget_amount" {
  description = "Monthly budget amount in USD"
  value       = azurerm_consumption_budget_subscription.monthly_cost_governance.amount
}

output "budget_time_period" {
  description = "Time period for the budget"
  value = {
    start_date = azurerm_consumption_budget_subscription.monthly_cost_governance.time_period[0].start_date
    end_date   = azurerm_consumption_budget_subscription.monthly_cost_governance.time_period[0].end_date
  }
}

# Azure Resource Graph Query Files
output "resource_graph_queries" {
  description = "Local file paths for Resource Graph queries"
  value = {
    cost_analysis_query   = local_file.cost_analysis_query.filename
    tag_compliance_query  = local_file.tag_compliance_query.filename
  }
}

# Azure Configuration Information
output "azure_subscription_id" {
  description = "Azure subscription ID where resources are deployed"
  value       = data.azurerm_client_config.current.subscription_id
}

output "azure_tenant_id" {
  description = "Azure tenant ID for the current subscription"
  value       = data.azurerm_client_config.current.tenant_id
}

output "azure_client_id" {
  description = "Azure client ID for the current authentication context"
  value       = data.azurerm_client_config.current.client_id
}

# Cost Management Information
output "cost_management_scope" {
  description = "Scope for Cost Management API access"
  value       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

output "cost_thresholds" {
  description = "Configured cost thresholds for monitoring"
  value = {
    monthly_threshold = var.cost_threshold_monthly
    daily_threshold   = var.cost_threshold_daily
  }
}

# Power BI Integration Information
output "powerbi_integration_guide" {
  description = "Instructions for connecting Power BI to the cost governance data"
  value = <<-EOT
    Power BI Integration Steps:
    1. Open Power BI Desktop
    2. Get Data -> Azure -> Azure Blob Storage
    3. Use Storage Account Name: ${azurerm_storage_account.cost_governance.name}
    4. Use Container: ${azurerm_storage_container.powerbi_datasets.name}
    5. Configure data refresh schedule for automated updates
    6. Create visualizations using cost and resource data
    
    Data Sources Available:
    - Resource Graph data: ${azurerm_storage_container.resource_graph_data.name}
    - Power BI datasets: ${azurerm_storage_container.powerbi_datasets.name}
    - Cost reports: ${azurerm_storage_container.cost_reports.name}
  EOT
}

# Security and Access Information
output "rbac_assignments" {
  description = "RBAC role assignments for cost governance access"
  value = {
    logic_app_cost_reader           = "Cost Management Reader"
    logic_app_reader                = "Reader"
    logic_app_storage_contributor   = "Storage Blob Data Contributor"
    logic_app_kv_secrets_user      = "Key Vault Secrets User"
    current_user_kv_secrets_officer = "Key Vault Secrets Officer"
  }
}

# Monitoring and Alerting Information
output "monitoring_configuration" {
  description = "Monitoring and alerting configuration summary"
  value = {
    logic_app_frequency = var.logic_app_frequency
    logic_app_interval  = var.logic_app_interval
    alert_email         = var.alert_email_address
    webhook_url         = var.webhook_url
    budget_thresholds = {
      actual_threshold     = var.budget_notification_threshold_actual
      forecasted_threshold = var.budget_notification_threshold_forecasted
    }
  }
}

# Network and Security Configuration
output "network_security_configuration" {
  description = "Network and security configuration for cost governance resources"
  value = {
    storage_https_only    = var.enable_https_traffic_only
    storage_min_tls       = var.minimum_tls_version
    kv_rbac_enabled       = var.enable_rbac_authorization
    kv_soft_delete        = var.enable_key_vault_soft_delete
    kv_purge_protection   = var.purge_protection_enabled
    network_default_action = var.network_access_default_action
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all cost governance resources"
  value       = var.resource_tags
}

# Cost Governance URLs and Endpoints
output "cost_governance_endpoints" {
  description = "Important URLs and endpoints for cost governance management"
  value = {
    azure_portal_resource_group = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.cost_governance.name}"
    azure_portal_logic_app      = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_logic_app_workflow.cost_monitoring.id}"
    azure_portal_storage        = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_account.cost_governance.id}"
    azure_portal_key_vault      = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.cost_governance.id}"
    azure_portal_budget         = "https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/BudgetsBlade"
    cost_management_portal      = "https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/overview"
    resource_graph_explorer     = "https://portal.azure.com/#blade/HubsExtension/ArgQueryBlade"
  }
}

# Generated Random Suffix
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}