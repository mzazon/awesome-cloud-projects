# ================================================================================================
# Azure Virtual Desktop Infrastructure Outputs
# 
# This file defines outputs for the Azure Virtual Desktop infrastructure,
# providing key information for verification, integration, and user access.
# ================================================================================================

# ------------------------------------------------------------------------------------------------
# Resource Group Information
# ------------------------------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the resource group containing all AVD infrastructure"
  value       = azurerm_resource_group.avd.name
}

output "resource_group_location" {
  description = "Azure region where the infrastructure is deployed"
  value       = azurerm_resource_group.avd.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.avd.id
}

# ------------------------------------------------------------------------------------------------
# Networking Information
# ------------------------------------------------------------------------------------------------

output "virtual_network_name" {
  description = "Name of the virtual network for AVD infrastructure"
  value       = azurerm_virtual_network.avd.name
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network"
  value       = azurerm_virtual_network.avd.id
}

output "virtual_network_address_space" {
  description = "Address space of the virtual network"
  value       = azurerm_virtual_network.avd.address_space
}

output "avd_subnet_name" {
  description = "Name of the subnet for AVD session hosts"
  value       = azurerm_subnet.avd_hosts.name
}

output "avd_subnet_id" {
  description = "Resource ID of the AVD hosts subnet"
  value       = azurerm_subnet.avd_hosts.id
}

output "avd_subnet_address_prefix" {
  description = "Address prefix of the AVD hosts subnet"
  value       = azurerm_subnet.avd_hosts.address_prefixes[0]
}

output "bastion_subnet_name" {
  description = "Name of the Azure Bastion subnet"
  value       = azurerm_subnet.bastion.name
}

output "bastion_subnet_id" {
  description = "Resource ID of the Bastion subnet"
  value       = azurerm_subnet.bastion.id
}

output "bastion_subnet_address_prefix" {
  description = "Address prefix of the Bastion subnet"
  value       = azurerm_subnet.bastion.address_prefixes[0]
}

# ------------------------------------------------------------------------------------------------
# Azure Bastion Information
# ------------------------------------------------------------------------------------------------

output "bastion_host_name" {
  description = "Name of the Azure Bastion host"
  value       = azurerm_bastion_host.avd.name
}

output "bastion_host_id" {
  description = "Resource ID of the Azure Bastion host"
  value       = azurerm_bastion_host.avd.id
}

output "bastion_public_ip_address" {
  description = "Public IP address of the Azure Bastion host"
  value       = azurerm_public_ip.bastion.ip_address
}

output "bastion_fqdn" {
  description = "Fully qualified domain name of the Azure Bastion host"
  value       = azurerm_public_ip.bastion.fqdn
}

output "bastion_sku" {
  description = "SKU of the Azure Bastion host"
  value       = azurerm_bastion_host.avd.sku
}

output "bastion_portal_url" {
  description = "Azure Portal URL for accessing Bastion"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_bastion_host.avd.id}/overview"
}

# ------------------------------------------------------------------------------------------------
# Azure Virtual Desktop Information
# ------------------------------------------------------------------------------------------------

output "host_pool_name" {
  description = "Name of the Azure Virtual Desktop host pool"
  value       = azurerm_virtual_desktop_host_pool.avd.name
}

output "host_pool_id" {
  description = "Resource ID of the host pool"
  value       = azurerm_virtual_desktop_host_pool.avd.id
}

output "host_pool_type" {
  description = "Type of the host pool (Personal or Pooled)"
  value       = azurerm_virtual_desktop_host_pool.avd.type
}

output "host_pool_load_balancer_type" {
  description = "Load balancer type for the host pool"
  value       = azurerm_virtual_desktop_host_pool.avd.load_balancer_type
}

output "host_pool_max_sessions" {
  description = "Maximum sessions allowed per session host"
  value       = azurerm_virtual_desktop_host_pool.avd.maximum_sessions_allowed
}

output "application_group_name" {
  description = "Name of the desktop application group"
  value       = azurerm_virtual_desktop_application_group.avd.name
}

output "application_group_id" {
  description = "Resource ID of the application group"
  value       = azurerm_virtual_desktop_application_group.avd.id
}

output "workspace_name" {
  description = "Name of the Azure Virtual Desktop workspace"
  value       = azurerm_virtual_desktop_workspace.avd.name
}

output "workspace_id" {
  description = "Resource ID of the workspace"
  value       = azurerm_virtual_desktop_workspace.avd.id
}

output "workspace_friendly_name" {
  description = "Friendly name of the workspace"
  value       = azurerm_virtual_desktop_workspace.avd.friendly_name
}

# ------------------------------------------------------------------------------------------------
# Session Host Information
# ------------------------------------------------------------------------------------------------

output "session_host_count" {
  description = "Number of session host VMs deployed"
  value       = length(azurerm_windows_virtual_machine.session_hosts)
}

output "session_host_names" {
  description = "Names of all session host virtual machines"
  value       = azurerm_windows_virtual_machine.session_hosts[*].name
}

output "session_host_ids" {
  description = "Resource IDs of all session host virtual machines"
  value       = azurerm_windows_virtual_machine.session_hosts[*].id
}

output "session_host_private_ips" {
  description = "Private IP addresses of all session host VMs"
  value       = azurerm_network_interface.session_hosts[*].private_ip_address
}

output "session_host_vm_size" {
  description = "VM size used for session hosts"
  value       = var.session_host_vm_size
}

output "session_host_admin_username" {
  description = "Administrator username for session host VMs"
  value       = var.session_host_admin_username
}

# ------------------------------------------------------------------------------------------------
# Security Information
# ------------------------------------------------------------------------------------------------

output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.avd.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.avd.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.avd.vault_uri
}

output "ssl_certificate_name" {
  description = "Name of the SSL certificate in Key Vault"
  value       = azurerm_key_vault_certificate.avd_ssl.name
}

output "ssl_certificate_id" {
  description = "Resource ID of the SSL certificate"
  value       = azurerm_key_vault_certificate.avd_ssl.id
}

output "ssl_certificate_thumbprint" {
  description = "Thumbprint of the SSL certificate"
  value       = azurerm_key_vault_certificate.avd_ssl.thumbprint
  sensitive   = true
}

output "network_security_group_name" {
  description = "Name of the network security group for AVD hosts"
  value       = azurerm_network_security_group.avd_hosts.name
}

output "network_security_group_id" {
  description = "Resource ID of the network security group"
  value       = azurerm_network_security_group.avd_hosts.id
}

# ------------------------------------------------------------------------------------------------
# Access Information
# ------------------------------------------------------------------------------------------------

output "avd_workspace_url" {
  description = "URL for accessing the Azure Virtual Desktop workspace"
  value       = "https://rdweb.wvd.microsoft.com/arm/webclient/index.html"
}

output "avd_web_client_url" {
  description = "Direct URL to the AVD web client for this workspace"
  value       = "https://client.wvd.microsoft.com/arm/webclient/index.html?workspaceId=${azurerm_virtual_desktop_workspace.avd.id}"
}

output "azure_portal_avd_url" {
  description = "Azure Portal URL for managing Azure Virtual Desktop"
  value       = "https://portal.azure.com/#view/Microsoft_Azure_WVD/WvdManagerMenuBlade/~/overview"
}

output "session_host_connection_info" {
  description = "Information for connecting to session hosts via Azure Bastion"
  value = {
    for i, vm in azurerm_windows_virtual_machine.session_hosts : vm.name => {
      vm_name           = vm.name
      private_ip        = azurerm_network_interface.session_hosts[i].private_ip_address
      bastion_host      = azurerm_bastion_host.avd.name
      admin_username    = var.session_host_admin_username
      connection_method = "Azure Bastion (via Azure Portal)"
    }
  }
}

# ------------------------------------------------------------------------------------------------
# Domain Join Information (if applicable)
# ------------------------------------------------------------------------------------------------

output "domain_join_status" {
  description = "Status of domain join configuration"
  value = var.domain_name != null ? {
    enabled     = true
    domain_name = var.domain_name
    ou_path     = var.ou_path
  } : {
    enabled = false
    message = "Domain join not configured - session hosts are workgroup members"
  }
}

# ------------------------------------------------------------------------------------------------
# Cost Management Information
# ------------------------------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = {
    session_hosts    = "VM costs: ~$${var.session_host_count * 150}/month (D4s_v3 VMs)"
    azure_bastion    = "Bastion: ~$140/month (Basic SKU)"
    networking       = "Networking: ~$5-20/month"
    key_vault        = "Key Vault: ~$1-5/month"
    avd_licensing    = "AVD: Included with eligible licenses or ~$4-6/user/month"
    total_estimate   = "Total: ~$${var.session_host_count * 150 + 140 + 15}/month (excluding AVD licensing)"
    note            = "Costs vary by region, usage patterns, and licensing agreements"
  }
}

# ------------------------------------------------------------------------------------------------
# Management Information
# ------------------------------------------------------------------------------------------------

output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

output "deployment_timestamp" {
  description = "Timestamp when this infrastructure was deployed"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "tags_applied" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# ------------------------------------------------------------------------------------------------
# Next Steps Information
# ------------------------------------------------------------------------------------------------

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Verify session hosts are registered in the host pool via Azure Portal",
    "2. Assign users or groups to the desktop application group",
    "3. Configure FSLogix profile containers for persistent user profiles",
    "4. Set up monitoring and alerting with Azure Monitor",
    "5. Configure auto-scaling policies for cost optimization",
    "6. Test user access via the AVD web client",
    "7. Use Azure Bastion to access session hosts for administration"
  ]
}

output "useful_commands" {
  description = "Useful Azure CLI commands for managing this infrastructure"
  value = {
    check_host_pool = "az desktopvirtualization hostpool show --name ${azurerm_virtual_desktop_host_pool.avd.name} --resource-group ${azurerm_resource_group.avd.name}"
    list_session_hosts = "az desktopvirtualization sessionhost list --host-pool-name ${azurerm_virtual_desktop_host_pool.avd.name} --resource-group ${azurerm_resource_group.avd.name}"
    check_bastion = "az network bastion show --name ${azurerm_bastion_host.avd.name} --resource-group ${azurerm_resource_group.avd.name}"
    view_workspace = "az desktopvirtualization workspace show --name ${azurerm_virtual_desktop_workspace.avd.name} --resource-group ${azurerm_resource_group.avd.name}"
  }
}