# Output values for Azure Confidential Computing deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Confidential Virtual Machine Information
output "confidential_vm_name" {
  description = "Name of the confidential virtual machine"
  value       = azurerm_linux_virtual_machine.confidential_vm.name
}

output "confidential_vm_id" {
  description = "ID of the confidential virtual machine"
  value       = azurerm_linux_virtual_machine.confidential_vm.id
}

output "confidential_vm_public_ip" {
  description = "Public IP address of the confidential VM"
  value       = azurerm_public_ip.vm_pip.ip_address
}

output "confidential_vm_private_ip" {
  description = "Private IP address of the confidential VM"
  value       = azurerm_network_interface.vm_nic.private_ip_address
}

output "confidential_vm_size" {
  description = "Size of the confidential virtual machine"
  value       = azurerm_linux_virtual_machine.confidential_vm.size
}

output "confidential_vm_admin_username" {
  description = "Administrator username for the confidential VM"
  value       = azurerm_linux_virtual_machine.confidential_vm.admin_username
}

# SSH Connection Information
output "ssh_private_key" {
  description = "Private SSH key for connecting to the confidential VM"
  value       = tls_private_key.vm_ssh_key.private_key_pem
  sensitive   = true
}

output "ssh_public_key" {
  description = "Public SSH key for the confidential VM"
  value       = tls_private_key.vm_ssh_key.public_key_openssh
}

output "ssh_connection_command" {
  description = "Command to SSH into the confidential VM"
  value       = "ssh -i vm_ssh_key.pem ${var.admin_username}@${azurerm_public_ip.vm_pip.ip_address}"
}

# Azure Attestation Information
output "attestation_provider_name" {
  description = "Name of the Azure Attestation provider"
  value       = azurerm_attestation_provider.main.name
}

output "attestation_provider_uri" {
  description = "URI of the Azure Attestation provider"
  value       = azurerm_attestation_provider.main.attestation_uri
}

output "attestation_provider_id" {
  description = "ID of the Azure Attestation provider"
  value       = azurerm_attestation_provider.main.id
}

# Managed HSM Information
output "managed_hsm_name" {
  description = "Name of the Azure Managed HSM"
  value       = azurerm_key_vault_managed_hardware_security_module.main.name
}

output "managed_hsm_uri" {
  description = "URI of the Azure Managed HSM"
  value       = azurerm_key_vault_managed_hardware_security_module.main.hsm_uri
}

output "managed_hsm_id" {
  description = "ID of the Azure Managed HSM"
  value       = azurerm_key_vault_managed_hardware_security_module.main.id
}

# Key Vault Information
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

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_container_name" {
  description = "Name of the confidential data storage container"
  value       = azurerm_storage_container.confidential_data.name
}

# Networking Information
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = var.create_virtual_network ? azurerm_virtual_network.main[0].name : null
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = var.create_virtual_network ? azurerm_virtual_network.main[0].id : null
}

output "vm_subnet_name" {
  description = "Name of the VM subnet"
  value       = var.create_virtual_network ? azurerm_subnet.vm_subnet[0].name : null
}

output "vm_subnet_id" {
  description = "ID of the VM subnet"
  value       = var.create_virtual_network ? azurerm_subnet.vm_subnet[0].id : null
}

# Managed Identity Information
output "vm_managed_identity_id" {
  description = "ID of the VM managed identity"
  value       = azurerm_user_assigned_identity.vm_identity.id
}

output "vm_managed_identity_client_id" {
  description = "Client ID of the VM managed identity"
  value       = azurerm_user_assigned_identity.vm_identity.client_id
}

output "vm_managed_identity_principal_id" {
  description = "Principal ID of the VM managed identity"
  value       = azurerm_user_assigned_identity.vm_identity.principal_id
}

output "storage_managed_identity_id" {
  description = "ID of the storage managed identity"
  value       = azurerm_user_assigned_identity.storage_identity.id
}

output "storage_managed_identity_client_id" {
  description = "Client ID of the storage managed identity"
  value       = azurerm_user_assigned_identity.storage_identity.client_id
}

# Encryption Key Information
output "encryption_key_name" {
  description = "Name of the encryption key in Key Vault"
  value       = azurerm_key_vault_key.enclave_master_key.name
}

output "encryption_key_id" {
  description = "ID of the encryption key in Key Vault"
  value       = azurerm_key_vault_key.enclave_master_key.id
}

output "encryption_key_version" {
  description = "Version of the encryption key"
  value       = azurerm_key_vault_key.enclave_master_key.version
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_diagnostics ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_diagnostics ? azurerm_log_analytics_workspace.main[0].id : null
}

# Security Information
output "network_security_group_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.vm_nsg.id
}

# Deployment Information
output "deployment_id" {
  description = "Unique identifier for this deployment"
  value       = random_string.suffix.result
}

output "tags" {
  description = "Tags applied to resources"
  value       = var.tags
}

# Verification Commands
output "verification_commands" {
  description = "Commands to verify the confidential computing deployment"
  value = {
    check_vm_confidential_features = "ssh -i vm_ssh_key.pem ${var.admin_username}@${azurerm_public_ip.vm_pip.ip_address} 'sudo dmesg | grep -i sev && ls -la /dev/sev-guest'"
    check_attestation_provider     = "az attestation show --name ${azurerm_attestation_provider.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_managed_hsm             = "az keyvault show --hsm-name ${azurerm_key_vault_managed_hardware_security_module.main.name} --query properties.provisioningState"
    check_key_vault               = "az keyvault show --name ${azurerm_key_vault.main.name} --query properties.provisioningState"
    list_hsm_keys                 = "az keyvault key list --hsm-name ${azurerm_key_vault_managed_hardware_security_module.main.name}"
    check_storage_encryption      = "az storage account show --name ${azurerm_storage_account.main.name} --query encryption"
    run_confidential_app          = "ssh -i vm_ssh_key.pem ${var.admin_username}@${azurerm_public_ip.vm_pip.ip_address} 'cd /opt/confidential-app && python3 confidential_app.py'"
  }
}

# Resource URLs for Azure Portal
output "azure_portal_urls" {
  description = "URLs to view resources in Azure Portal"
  value = {
    resource_group      = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.main.id}"
    confidential_vm     = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_linux_virtual_machine.confidential_vm.id}"
    attestation_provider = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_attestation_provider.main.id}"
    managed_hsm         = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault_managed_hardware_security_module.main.id}"
    key_vault          = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.main.id}"
    storage_account    = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_account.main.id}"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    confidential_vm_dc4as_v5 = "~$400-500/month"
    managed_hsm_standard_b1  = "~$200-300/month"
    key_vault_premium        = "~$10-20/month"
    storage_account_premium  = "~$10-50/month"
    attestation_provider     = "~$1-5/month"
    networking_components    = "~$5-15/month"
    log_analytics           = "~$5-20/month"
    total_estimated         = "~$630-910/month"
    note                    = "Costs vary by region and usage. Managed HSM is the primary cost driver."
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Save the SSH private key to a secure location: terraform output -raw ssh_private_key > vm_ssh_key.pem && chmod 600 vm_ssh_key.pem",
    "2. Connect to the confidential VM using the SSH command provided in the output",
    "3. Verify confidential computing features are enabled using the verification commands",
    "4. Initialize the Managed HSM security domain for production use",
    "5. Configure custom attestation policies for your specific use case",
    "6. Deploy your confidential applications to the secure environment",
    "7. Set up monitoring and alerting for the confidential computing infrastructure",
    "8. Review and implement additional security hardening measures"
  ]
}