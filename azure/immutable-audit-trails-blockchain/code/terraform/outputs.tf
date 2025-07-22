# Outputs for Azure Confidential Ledger Audit Trail Infrastructure
# This file defines the output values that will be displayed after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.audit_trail.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.audit_trail.location
}

# Confidential Ledger Information
output "confidential_ledger_name" {
  description = "Name of the Azure Confidential Ledger"
  value       = azurerm_confidential_ledger.audit_trail.name
}

output "confidential_ledger_uri" {
  description = "URI endpoint for the Azure Confidential Ledger"
  value       = azurerm_confidential_ledger.audit_trail.ledger_uri
}

output "confidential_ledger_id" {
  description = "Resource ID of the Azure Confidential Ledger"
  value       = azurerm_confidential_ledger.audit_trail.id
}

output "confidential_ledger_type" {
  description = "Type of the Confidential Ledger (Public or Private)"
  value       = azurerm_confidential_ledger.audit_trail.ledger_type
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.audit_trail.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.audit_trail.vault_uri
}

output "key_vault_id" {
  description = "Resource ID of the Azure Key Vault"
  value       = azurerm_key_vault.audit_trail.id
}

# Event Hub Information
output "event_hub_namespace_name" {
  description = "Name of the Event Hub Namespace"
  value       = azurerm_eventhub_namespace.audit_trail.name
}

output "event_hub_name" {
  description = "Name of the Event Hub for audit events"
  value       = azurerm_eventhub.audit_events.name
}

output "event_hub_connection_string" {
  description = "Connection string for the Event Hub (sensitive)"
  value       = azurerm_eventhub_authorization_rule.audit_events_rule.primary_connection_string
  sensitive   = true
}

output "event_hub_namespace_fqdn" {
  description = "Fully qualified domain name of the Event Hub Namespace"
  value       = "${azurerm_eventhub_namespace.audit_trail.name}.servicebus.windows.net"
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = azurerm_storage_account.audit_trail.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the Storage Account"
  value       = azurerm_storage_account.audit_trail.primary_blob_endpoint
}

output "storage_account_id" {
  description = "Resource ID of the Storage Account"
  value       = azurerm_storage_account.audit_trail.id
}

output "storage_container_name" {
  description = "Name of the storage container for audit archives"
  value       = azurerm_storage_container.audit_archive.name
}

output "storage_connection_string" {
  description = "Connection string for the Storage Account (sensitive)"
  value       = azurerm_storage_account.audit_trail.primary_connection_string
  sensitive   = true
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App"
  value       = azurerm_logic_app_workflow.audit_trail.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App"
  value       = azurerm_logic_app_workflow.audit_trail.id
}

output "logic_app_callback_url" {
  description = "Callback URL for the Logic App workflow"
  value       = azurerm_logic_app_workflow.audit_trail.callback_url
  sensitive   = true
}

output "logic_app_managed_identity_principal_id" {
  description = "Principal ID of the Logic App's managed identity"
  value       = azurerm_logic_app_workflow.audit_trail_identity.identity[0].principal_id
}

output "logic_app_managed_identity_tenant_id" {
  description = "Tenant ID of the Logic App's managed identity"
  value       = azurerm_logic_app_workflow.audit_trail_identity.identity[0].tenant_id
}

# Log Analytics Workspace Information (if created)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace (if created)"
  value       = var.enable_diagnostic_settings && var.log_analytics_workspace_id == null ? azurerm_log_analytics_workspace.audit_trail[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = var.enable_diagnostic_settings ? (var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.audit_trail[0].id) : null
}

# Private Endpoint Information (if enabled)
output "private_endpoint_keyvault_ip" {
  description = "Private IP address of the Key Vault private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.keyvault[0].private_service_connection[0].private_ip_address : null
}

output "private_endpoint_storage_ip" {
  description = "Private IP address of the Storage Account private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.storage[0].private_service_connection[0].private_ip_address : null
}

output "private_endpoint_eventhub_ip" {
  description = "Private IP address of the Event Hub private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.eventhub[0].private_service_connection[0].private_ip_address : null
}

# Security Information
output "key_vault_secrets_stored" {
  description = "List of secrets stored in Key Vault"
  value = [
    azurerm_key_vault_secret.ledger_endpoint.name,
    azurerm_key_vault_secret.eventhub_connection.name,
    azurerm_key_vault_secret.storage_connection.name
  ]
}

output "rbac_assignments_created" {
  description = "Summary of RBAC assignments created"
  value = {
    "Key Vault Administrator" = data.azurerm_client_config.current.object_id
    "Key Vault Secrets User" = azurerm_logic_app_workflow.audit_trail_identity.identity[0].principal_id
    "Event Hubs Data Receiver" = azurerm_logic_app_workflow.audit_trail_identity.identity[0].principal_id
    "Storage Blob Data Contributor" = azurerm_logic_app_workflow.audit_trail_identity.identity[0].principal_id
    "Confidential Ledger User" = azurerm_logic_app_workflow.audit_trail_identity.identity[0].principal_id
  }
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed audit trail infrastructure"
  value = {
    resource_group = azurerm_resource_group.audit_trail.name
    location = azurerm_resource_group.audit_trail.location
    confidential_ledger = azurerm_confidential_ledger.audit_trail.name
    key_vault = azurerm_key_vault.audit_trail.name
    event_hub_namespace = azurerm_eventhub_namespace.audit_trail.name
    storage_account = azurerm_storage_account.audit_trail.name
    logic_app = azurerm_logic_app_workflow.audit_trail.name
    diagnostic_settings_enabled = var.enable_diagnostic_settings
    private_endpoints_enabled = var.enable_private_endpoints
    random_suffix = random_string.suffix.result
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps to complete the audit trail setup"
  value = [
    "1. Configure Logic App workflow definition to process audit events",
    "2. Set up Event Hub producers to send audit events",
    "3. Configure diagnostic settings for additional Azure resources",
    "4. Set up monitoring and alerting for audit trail activities",
    "5. Test the end-to-end audit trail flow with sample events",
    "6. Configure retention policies for archived audit data",
    "7. Set up backup and disaster recovery procedures"
  ]
}

# Cost Estimation Information
output "cost_estimation_notes" {
  description = "Notes about expected costs for the audit trail infrastructure"
  value = [
    "Confidential Ledger: ~$100-150/month for base infrastructure + transaction costs",
    "Key Vault: ~$5-10/month for standard operations",
    "Event Hub: ~$20-50/month depending on throughput requirements",
    "Storage Account: ~$5-20/month depending on data volume",
    "Logic App: ~$10-30/month depending on execution frequency",
    "Log Analytics: ~$10-50/month depending on data ingestion volume",
    "Total estimated cost: ~$150-300/month for moderate usage"
  ]
}

# Security Configuration Summary
output "security_features_enabled" {
  description = "Summary of security features enabled"
  value = {
    key_vault_soft_delete = true
    key_vault_purge_protection = true
    key_vault_rbac = true
    storage_versioning = true
    managed_identity = true
    private_endpoints = var.enable_private_endpoints
    diagnostic_logging = var.enable_diagnostic_settings
  }
}