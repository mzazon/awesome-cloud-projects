# Outputs for SCOM Migration to Azure Monitor SCOM Managed Instance
# This file defines all the output values that will be displayed after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all SCOM migration resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Network Configuration Outputs
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "scom_subnet_id" {
  description = "ID of the SCOM Managed Instance subnet"
  value       = azurerm_subnet.scom_mi.id
}

output "scom_subnet_name" {
  description = "Name of the SCOM Managed Instance subnet"
  value       = azurerm_subnet.scom_mi.name
}

output "sql_subnet_id" {
  description = "ID of the SQL Managed Instance subnet"
  value       = azurerm_subnet.sql_mi.id
}

output "sql_subnet_name" {
  description = "Name of the SQL Managed Instance subnet"
  value       = azurerm_subnet.sql_mi.name
}

# SQL Managed Instance Outputs
output "sql_managed_instance_name" {
  description = "Name of the SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.main.name
}

output "sql_managed_instance_id" {
  description = "ID of the SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.main.id
}

output "sql_managed_instance_fqdn" {
  description = "Fully qualified domain name of the SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.main.fqdn
}

output "sql_managed_instance_public_fqdn" {
  description = "Public fully qualified domain name of the SQL Managed Instance"
  value       = "${azurerm_mssql_managed_instance.main.name}.public.${azurerm_mssql_managed_instance.main.dns_zone_id}.database.windows.net"
}

output "sql_admin_username" {
  description = "Administrator username for SQL Managed Instance"
  value       = var.sql_admin_username
}

output "sql_managed_instance_vcores" {
  description = "Number of vCores for SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.main.vcores
}

output "sql_managed_instance_storage_size" {
  description = "Storage size in GB for SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.main.storage_size_in_gb
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Managed Identity Outputs
output "managed_identity_name" {
  description = "Name of the user assigned managed identity"
  value       = azurerm_user_assigned_identity.scom_mi.name
}

output "managed_identity_id" {
  description = "ID of the user assigned managed identity"
  value       = azurerm_user_assigned_identity.scom_mi.id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user assigned managed identity"
  value       = azurerm_user_assigned_identity.scom_mi.principal_id
}

output "managed_identity_client_id" {
  description = "Client ID of the user assigned managed identity"
  value       = azurerm_user_assigned_identity.scom_mi.client_id
}

# Log Analytics Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for migration"
  value       = azurerm_storage_account.migration.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.migration.id
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.migration.primary_blob_endpoint
}

output "management_packs_container_name" {
  description = "Name of the management packs storage container"
  value       = azurerm_storage_container.management_packs.name
}

# Action Group Outputs
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "ID of the action group"
  value       = azurerm_monitor_action_group.main.id
}

# Network Security Group Outputs
output "scom_nsg_name" {
  description = "Name of the SCOM network security group"
  value       = azurerm_network_security_group.scom_mi.name
}

output "scom_nsg_id" {
  description = "ID of the SCOM network security group"
  value       = azurerm_network_security_group.scom_mi.id
}

output "sql_nsg_name" {
  description = "Name of the SQL network security group"
  value       = azurerm_network_security_group.sql_mi.name
}

output "sql_nsg_id" {
  description = "ID of the SQL network security group"
  value       = azurerm_network_security_group.sql_mi.id
}

# SCOM Managed Instance Configuration Information
output "scom_managed_instance_name" {
  description = "Name that will be used for SCOM Managed Instance"
  value       = local.scom_mi_name
}

output "scom_domain_configuration" {
  description = "Domain configuration for SCOM Managed Instance"
  value = {
    domain_name = var.scom_domain_name
    domain_user = var.scom_domain_user_name
  }
}

# Connection Information
output "sql_connection_details" {
  description = "SQL Managed Instance connection details"
  value = {
    server_name = azurerm_mssql_managed_instance.main.fqdn
    public_endpoint = "${azurerm_mssql_managed_instance.main.name}.public.${azurerm_mssql_managed_instance.main.dns_zone_id}.database.windows.net"
    port = 3342
    admin_user = var.sql_admin_username
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Instructions for completing the SCOM Managed Instance deployment"
  value = {
    step_1 = "SQL Managed Instance has been created and is ready for use"
    step_2 = "Create SCOM Managed Instance using Azure CLI or portal with the following parameters:"
    scom_mi_name = local.scom_mi_name
    sql_mi_id = azurerm_mssql_managed_instance.main.id
    subnet_id = azurerm_subnet.scom_mi.id
    managed_identity_id = azurerm_user_assigned_identity.scom_mi.id
    key_vault_uri = azurerm_key_vault.main.vault_uri
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.workspace_id
  }
}

# Azure CLI Commands for SCOM MI Creation
output "azure_cli_commands" {
  description = "Azure CLI commands to create SCOM Managed Instance"
  value = {
    create_scom_mi = "az monitor scom-managed-instance create --name ${local.scom_mi_name} --resource-group ${azurerm_resource_group.main.name} --location ${azurerm_resource_group.main.location} --sql-managed-instance-id ${azurerm_mssql_managed_instance.main.id} --subnet-id ${azurerm_subnet.scom_mi.id} --managed-identity-id ${azurerm_user_assigned_identity.scom_mi.id} --key-vault-uri ${azurerm_key_vault.main.vault_uri}"
    check_status = "az monitor scom-managed-instance show --name ${local.scom_mi_name} --resource-group ${azurerm_resource_group.main.name} --query provisioningState --output tsv"
    configure_log_analytics = "az monitor scom-managed-instance update --name ${local.scom_mi_name} --resource-group ${azurerm_resource_group.main.name} --log-analytics-workspace-id ${azurerm_log_analytics_workspace.main.workspace_id}"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for deployed resources"
  value = {
    sql_managed_instance = "Approximately $${var.sql_vcores * 200} per month for ${var.sql_vcores} vCores"
    storage_costs = "Approximately $${var.sql_storage_size_gb * 0.115} per month for ${var.sql_storage_size_gb} GB storage"
    log_analytics = "Pay-per-GB ingestion and retention costs"
    storage_account = "Minimal cost for management pack storage"
    networking = "Standard networking charges apply"
    note = "SCOM Managed Instance pricing varies based on monitored resources"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    key_vault_name = azurerm_key_vault.main.name
    managed_identity_name = azurerm_user_assigned_identity.scom_mi.name
    tls_version = "1.2"
    encryption_enabled = true
    network_security_groups = [
      azurerm_network_security_group.scom_mi.name,
      azurerm_network_security_group.sql_mi.name
    ]
    allowed_ports = {
      scom_agents = "5723"
      scom_console = "5724"
      web_console = "80, 443"
      sql_mi = "1433, 3342"
    }
  }
}

# Monitoring Configuration
output "monitoring_configuration" {
  description = "Monitoring and alerting configuration"
  value = {
    log_analytics_workspace = azurerm_log_analytics_workspace.main.name
    action_group = azurerm_monitor_action_group.main.name
    diagnostic_settings_enabled = var.enable_diagnostics
    retention_days = var.log_analytics_retention_days
    alert_email_receivers = var.alert_email_receivers
  }
}

# Backup Configuration
output "backup_configuration" {
  description = "Backup configuration for SQL Managed Instance"
  value = {
    backup_enabled = var.enable_backup
    retention_days = var.backup_retention_days
    storage_account_type = azurerm_mssql_managed_instance.main.storage_account_type
    point_in_time_restore = "Supported"
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps after infrastructure deployment"
  value = {
    step_1 = "Wait for SQL Managed Instance to be fully provisioned (may take 4-6 hours)"
    step_2 = "Create SCOM Managed Instance using provided Azure CLI commands"
    step_3 = "Configure network connectivity from on-premises environment"
    step_4 = "Upload management packs to storage account"
    step_5 = "Import management packs into SCOM Managed Instance"
    step_6 = "Configure agent multi-homing for gradual migration"
    step_7 = "Validate monitoring data collection and alerting"
    step_8 = "Complete migration and decommission on-premises SCOM"
  }
}

# Troubleshooting Information
output "troubleshooting" {
  description = "Common troubleshooting information"
  value = {
    sql_mi_creation_time = "4-6 hours for initial provisioning"
    network_connectivity = "Verify NSG rules and routing tables"
    key_vault_access = "Check managed identity permissions"
    log_analytics_ingestion = "Allow up to 10 minutes for data to appear"
    support_resources = "Azure Support, Microsoft Documentation, Community Forums"
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value = local.common_tags
}