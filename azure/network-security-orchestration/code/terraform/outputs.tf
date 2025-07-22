# Output Values for Azure Network Security Orchestration
# This file defines the output values that will be displayed after deployment
# These outputs provide important information for validation and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Logic Apps Information
output "logic_app_name" {
  description = "Name of the Logic Apps workflow"
  value       = azurerm_logic_app_workflow.main.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic Apps workflow"
  value       = azurerm_logic_app_workflow.main.id
}

output "logic_app_state" {
  description = "Current state of the Logic Apps workflow"
  value       = azurerm_logic_app_workflow.main.enabled ? "Enabled" : "Disabled"
}

output "logic_app_access_endpoint" {
  description = "Access endpoint for the Logic Apps workflow"
  value       = azurerm_logic_app_workflow.main.access_endpoint
  sensitive   = true
}

# Network Security Group Information
output "network_security_group_name" {
  description = "Name of the Network Security Group"
  value       = azurerm_network_security_group.main.name
}

output "network_security_group_id" {
  description = "Resource ID of the Network Security Group"
  value       = azurerm_network_security_group.main.id
}

output "network_security_group_location" {
  description = "Location of the Network Security Group"
  value       = azurerm_network_security_group.main.location
}

# Virtual Network Information
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "virtual_network_address_space" {
  description = "Address space of the virtual network"
  value       = azurerm_virtual_network.main.address_space
}

# Subnet Information
output "protected_subnet_name" {
  description = "Name of the protected subnet"
  value       = azurerm_subnet.protected.name
}

output "protected_subnet_id" {
  description = "Resource ID of the protected subnet"
  value       = azurerm_subnet.protected.id
}

output "protected_subnet_address_prefixes" {
  description = "Address prefixes of the protected subnet"
  value       = azurerm_subnet.protected.address_prefixes
}

output "management_subnet_name" {
  description = "Name of the management subnet"
  value       = azurerm_subnet.management.name
}

output "management_subnet_id" {
  description = "Resource ID of the management subnet"
  value       = azurerm_subnet.management.id
}

output "management_subnet_address_prefixes" {
  description = "Address prefixes of the management subnet"
  value       = azurerm_subnet.management.address_prefixes
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
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
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Storage Container Information
output "security_events_container_name" {
  description = "Name of the security events storage container"
  value       = azurerm_storage_container.security_events.name
}

output "compliance_reports_container_name" {
  description = "Name of the compliance reports storage container"
  value       = azurerm_storage_container.compliance_reports.name
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Managed Identity Information
output "logic_apps_managed_identity_name" {
  description = "Name of the Logic Apps managed identity"
  value       = azurerm_user_assigned_identity.logic_apps.name
}

output "logic_apps_managed_identity_id" {
  description = "Resource ID of the Logic Apps managed identity"
  value       = azurerm_user_assigned_identity.logic_apps.id
}

output "logic_apps_managed_identity_principal_id" {
  description = "Principal ID of the Logic Apps managed identity"
  value       = azurerm_user_assigned_identity.logic_apps.principal_id
}

output "logic_apps_managed_identity_client_id" {
  description = "Client ID of the Logic Apps managed identity"
  value       = azurerm_user_assigned_identity.logic_apps.client_id
}

# Monitoring Information
output "action_group_name" {
  description = "Name of the Azure Monitor action group"
  value       = azurerm_monitor_action_group.security_orchestration.name
}

output "action_group_id" {
  description = "Resource ID of the Azure Monitor action group"
  value       = azurerm_monitor_action_group.security_orchestration.id
}

output "metric_alert_name" {
  description = "Name of the metric alert for suspicious activity"
  value       = azurerm_monitor_metric_alert.suspicious_activity.name
}

output "metric_alert_id" {
  description = "Resource ID of the metric alert for suspicious activity"
  value       = azurerm_monitor_metric_alert.suspicious_activity.id
}

output "activity_log_alert_name" {
  description = "Name of the activity log alert for NSG modifications"
  value       = azurerm_monitor_activity_log_alert.nsg_modifications.name
}

output "activity_log_alert_id" {
  description = "Resource ID of the activity log alert for NSG modifications"
  value       = azurerm_monitor_activity_log_alert.nsg_modifications.id
}

# Security Configuration
output "default_security_rules" {
  description = "List of default security rules applied to the NSG"
  value       = [for rule_name, rule in var.default_security_rules : "${rule_name}: ${rule.access} ${rule.protocol}/${rule.destination_port_range}"]
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "terraform_version" {
  description = "Version of Terraform used for deployment"
  value       = "~> 1.0"
}

output "azurerm_provider_version" {
  description = "Version of AzureRM provider used for deployment"
  value       = "~> 3.0"
}

# Resource Naming Information
output "resource_naming_convention" {
  description = "Naming convention used for resources"
  value = {
    prefix         = local.resource_prefix
    suffix         = local.suffix
    resource_group = local.resource_group_name
    location       = var.location
    environment    = var.environment
    project        = var.project_name
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_logic_app = "az logic workflow show --name ${azurerm_logic_app_workflow.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_nsg_rules = "az network nsg show --name ${azurerm_network_security_group.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_key_vault = "az keyvault show --name ${azurerm_key_vault.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_storage   = "az storage account show --name ${azurerm_storage_account.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_log_analytics = "az monitor log-analytics workspace show --workspace-name ${azurerm_log_analytics_workspace.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Cost Management Information
output "cost_management_tags" {
  description = "Tags applied to resources for cost management"
  value       = local.common_tags
}

# Security Endpoints
output "security_endpoints" {
  description = "Important security endpoints for monitoring and management"
  value = {
    key_vault_uri           = azurerm_key_vault.main.vault_uri
    log_analytics_portal   = "https://portal.azure.com/#resource${azurerm_log_analytics_workspace.main.id}"
    logic_apps_portal      = "https://portal.azure.com/#resource${azurerm_logic_app_workflow.main.id}"
    network_security_group = "https://portal.azure.com/#resource${azurerm_network_security_group.main.id}"
  }
  sensitive = true
}

# Compliance Information
output "compliance_information" {
  description = "Information relevant for compliance and auditing"
  value = {
    diagnostic_settings_enabled = var.enable_diagnostic_settings
    log_retention_days         = var.log_analytics_retention_days
    key_vault_soft_delete_days = var.key_vault_soft_delete_retention_days
    storage_encryption_enabled = true
    https_only_enabled         = true
    min_tls_version           = "1.2"
  }
}