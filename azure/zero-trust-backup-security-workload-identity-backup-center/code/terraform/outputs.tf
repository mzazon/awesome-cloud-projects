# outputs.tf - Output values for the zero-trust backup security solution
# This file defines all outputs that will be displayed after deployment

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
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Workload Identity Information
output "workload_identity_name" {
  description = "Name of the workload identity"
  value       = azurerm_user_assigned_identity.workload_identity.name
}

output "workload_identity_client_id" {
  description = "Client ID of the workload identity for external authentication"
  value       = azurerm_user_assigned_identity.workload_identity.client_id
}

output "workload_identity_principal_id" {
  description = "Principal ID of the workload identity"
  value       = azurerm_user_assigned_identity.workload_identity.principal_id
}

output "workload_identity_tenant_id" {
  description = "Tenant ID for workload identity authentication"
  value       = data.azurerm_client_config.current.tenant_id
}

# Key Vault Information
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

output "key_vault_tenant_id" {
  description = "Tenant ID of the Key Vault"
  value       = azurerm_key_vault.main.tenant_id
}

# Recovery Services Vault Information
output "recovery_vault_name" {
  description = "Name of the Recovery Services Vault"
  value       = azurerm_recovery_services_vault.main.name
}

output "recovery_vault_id" {
  description = "ID of the Recovery Services Vault"
  value       = azurerm_recovery_services_vault.main.id
}

output "recovery_vault_storage_mode" {
  description = "Storage mode of the Recovery Services Vault"
  value       = azurerm_recovery_services_vault.main.storage_mode_type
}

output "recovery_vault_cross_region_restore" {
  description = "Cross-region restore status of the Recovery Services Vault"
  value       = azurerm_recovery_services_vault.main.cross_region_restore_enabled
}

# Backup Policy Information
output "backup_policy_name" {
  description = "Name of the VM backup policy"
  value       = azurerm_backup_policy_vm.zero_trust_policy.name
}

output "backup_policy_id" {
  description = "ID of the VM backup policy"
  value       = azurerm_backup_policy_vm.zero_trust_policy.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for backup reports"
  value       = azurerm_storage_account.backup_reports.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.backup_reports.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.backup_reports.primary_blob_endpoint
}

output "storage_container_name" {
  description = "Name of the backup reports container"
  value       = azurerm_storage_container.backup_reports.name
}

# Log Analytics Workspace Information
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.backup_center[0].id : null
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.backup_center[0].name : null
}

# Virtual Machine Information (if created)
output "vm_name" {
  description = "Name of the test virtual machine (if created)"
  value       = var.enable_vm_creation ? azurerm_linux_virtual_machine.test_vm[0].name : null
}

output "vm_id" {
  description = "ID of the test virtual machine (if created)"
  value       = var.enable_vm_creation ? azurerm_linux_virtual_machine.test_vm[0].id : null
}

output "vm_public_ip" {
  description = "Public IP address of the test virtual machine (if created)"
  value       = var.enable_vm_creation ? azurerm_public_ip.test_pip[0].ip_address : null
}

output "vm_private_ip" {
  description = "Private IP address of the test virtual machine (if created)"
  value       = var.enable_vm_creation ? azurerm_network_interface.test_nic[0].private_ip_address : null
}

output "vm_backup_protected" {
  description = "Whether the VM is protected by backup (if created and backup enabled)"
  value       = var.enable_vm_creation && var.enable_backup_protection ? true : false
}

# Network Information (if VM created)
output "virtual_network_name" {
  description = "Name of the virtual network (if VM created)"
  value       = var.enable_vm_creation ? azurerm_virtual_network.test_vnet[0].name : null
}

output "virtual_network_id" {
  description = "ID of the virtual network (if VM created)"
  value       = var.enable_vm_creation ? azurerm_virtual_network.test_vnet[0].id : null
}

output "subnet_id" {
  description = "ID of the subnet (if VM created)"
  value       = var.enable_vm_creation ? azurerm_subnet.test_subnet[0].id : null
}

# Secret Names in Key Vault
output "key_vault_secrets" {
  description = "List of secret names stored in Key Vault"
  value = [
    azurerm_key_vault_secret.backup_storage_key.name,
    azurerm_key_vault_secret.sql_connection_string.name
  ]
}

output "key_vault_certificate_name" {
  description = "Name of the backup encryption certificate in Key Vault"
  value       = azurerm_key_vault_certificate.backup_encryption_cert.name
}

# Federated Identity Credentials Information
output "federated_identity_credentials" {
  description = "List of federated identity credentials created"
  value = var.enable_federated_credentials ? [
    for cred in var.federated_identity_credentials : {
      name        = cred.name
      issuer      = cred.issuer
      subject     = cred.subject
      audience    = cred.audience
      description = cred.description
    }
  ] : []
}

# Azure Configuration for External Systems
output "azure_configuration" {
  description = "Azure configuration values for external systems"
  value = {
    subscription_id = var.subscription_id
    tenant_id       = data.azurerm_client_config.current.tenant_id
    client_id       = azurerm_user_assigned_identity.workload_identity.client_id
    resource_group  = azurerm_resource_group.main.name
    location        = azurerm_resource_group.main.location
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group_name    = azurerm_resource_group.main.name
    key_vault_name        = azurerm_key_vault.main.name
    recovery_vault_name   = azurerm_recovery_services_vault.main.name
    workload_identity_name = azurerm_user_assigned_identity.workload_identity.name
    storage_account_name  = azurerm_storage_account.backup_reports.name
    vm_created           = var.enable_vm_creation
    backup_enabled       = var.enable_vm_creation && var.enable_backup_protection
    monitoring_enabled   = var.enable_monitoring
    federated_creds_count = var.enable_federated_credentials ? length(var.federated_identity_credentials) : 0
  }
}

# Connection Instructions
output "connection_instructions" {
  description = "Instructions for connecting to deployed resources"
  value = {
    key_vault_access = "Use Azure CLI: az keyvault secret show --vault-name ${azurerm_key_vault.main.name} --name <secret-name>"
    vm_ssh_command   = var.enable_vm_creation ? "ssh ${var.vm_admin_username}@${azurerm_public_ip.test_pip[0].ip_address}" : "VM not created"
    backup_monitoring = "Access Azure Backup Center in Azure Portal for centralized backup management"
    workload_identity = "Configure external systems with Client ID: ${azurerm_user_assigned_identity.workload_identity.client_id}"
  }
}

# Security Information
output "security_features" {
  description = "Security features implemented in the deployment"
  value = {
    key_vault_rbac_enabled     = azurerm_key_vault.main.enable_rbac_authorization
    key_vault_purge_protection = azurerm_key_vault.main.purge_protection_enabled
    key_vault_soft_delete     = true
    recovery_vault_soft_delete = azurerm_recovery_services_vault.main.soft_delete_enabled
    cross_region_restore      = azurerm_recovery_services_vault.main.cross_region_restore_enabled
    storage_https_only        = azurerm_storage_account.backup_reports.https_traffic_only_enabled
    min_tls_version          = azurerm_storage_account.backup_reports.min_tls_version
  }
}

# Cost Monitoring Information
output "cost_monitoring_resources" {
  description = "Resources that will incur costs"
  value = {
    key_vault              = "Premium SKU - ${azurerm_key_vault.main.sku_name}"
    recovery_services_vault = "Standard SKU with ${azurerm_recovery_services_vault.main.storage_mode_type} storage"
    storage_account        = "${azurerm_storage_account.backup_reports.account_tier} tier with ${azurerm_storage_account.backup_reports.account_replication_type} replication"
    virtual_machine        = var.enable_vm_creation ? "VM Size: ${var.vm_size}" : "No VM created"
    log_analytics         = var.enable_monitoring ? "PerGB2018 pricing tier" : "Not enabled"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    "1_configure_backup_policies" = "Review and adjust backup policies in ${azurerm_backup_policy_vm.zero_trust_policy.name}"
    "2_setup_monitoring"         = var.enable_monitoring ? "Configure alerts in Log Analytics workspace ${azurerm_log_analytics_workspace.backup_center[0].name}" : "Enable monitoring by setting enable_monitoring = true"
    "3_test_backup_operations"   = var.enable_vm_creation && var.enable_backup_protection ? "Test backup and restore operations for VM ${azurerm_linux_virtual_machine.test_vm[0].name}" : "Create VM and enable backup protection"
    "4_configure_external_access" = "Configure external systems with the federated identity credentials"
    "5_review_security_settings" = "Review and adjust Key Vault network ACLs and security settings"
  }
}