# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the resource group containing all zero-trust infrastructure"
  value       = azurerm_resource_group.zerotrust.name
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.zerotrust.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.zerotrust.location
}

# Network Infrastructure Outputs
output "hub_vnet_id" {
  description = "Resource ID of the hub virtual network"
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  description = "Name of the hub virtual network"
  value       = azurerm_virtual_network.hub.name
}

output "spoke_vnet_ids" {
  description = "Resource IDs of all spoke virtual networks"
  value = {
    for key, vnet in azurerm_virtual_network.spoke : key => vnet.id
  }
}

output "spoke_vnet_names" {
  description = "Names of all spoke virtual networks"
  value = {
    for key, vnet in azurerm_virtual_network.spoke : key => vnet.name
  }
}

# Azure Bastion Outputs
output "bastion_id" {
  description = "Resource ID of Azure Bastion"
  value       = azurerm_bastion_host.zerotrust.id
}

output "bastion_name" {
  description = "Name of Azure Bastion"
  value       = azurerm_bastion_host.zerotrust.name
}

output "bastion_fqdn" {
  description = "Fully qualified domain name of Azure Bastion"
  value       = azurerm_bastion_host.zerotrust.dns_name
}

output "bastion_public_ip" {
  description = "Public IP address of Azure Bastion"
  value       = azurerm_public_ip.bastion.ip_address
}

output "bastion_sku" {
  description = "SKU of Azure Bastion"
  value       = azurerm_bastion_host.zerotrust.sku
}

# Azure Firewall Outputs
output "firewall_id" {
  description = "Resource ID of Azure Firewall"
  value       = azurerm_firewall.zerotrust.id
}

output "firewall_name" {
  description = "Name of Azure Firewall"
  value       = azurerm_firewall.zerotrust.name
}

output "firewall_private_ip" {
  description = "Private IP address of Azure Firewall"
  value       = azurerm_firewall.zerotrust.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "Public IP address of Azure Firewall"
  value       = azurerm_public_ip.firewall.ip_address
}

output "firewall_sku_tier" {
  description = "SKU tier of Azure Firewall"
  value       = azurerm_firewall.zerotrust.sku_tier
}

# Firewall Policy Outputs
output "firewall_policy_id" {
  description = "Resource ID of Azure Firewall Policy"
  value       = azurerm_firewall_policy.zerotrust.id
}

output "firewall_policy_name" {
  description = "Name of Azure Firewall Policy"
  value       = azurerm_firewall_policy.zerotrust.name
}

# Network Security Group Outputs
output "nsg_ids" {
  description = "Resource IDs of Network Security Groups"
  value = {
    for key, nsg in azurerm_network_security_group.spoke_workload : key => nsg.id
  }
}

output "nsg_names" {
  description = "Names of Network Security Groups"
  value = {
    for key, nsg in azurerm_network_security_group.spoke_workload : key => nsg.name
  }
}

# Route Table Outputs
output "route_table_id" {
  description = "Resource ID of the route table for forced tunneling"
  value       = azurerm_route_table.spoke_workloads.id
}

output "route_table_name" {
  description = "Name of the route table for forced tunneling"
  value       = azurerm_route_table.spoke_workloads.name
}

# Monitoring Outputs
output "log_analytics_workspace_id" {
  description = "Resource ID of Log Analytics workspace"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.zerotrust[0].id : null
}

output "log_analytics_workspace_name" {
  description = "Name of Log Analytics workspace"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.zerotrust[0].name : null
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of Log Analytics workspace (used for agent configuration)"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.zerotrust[0].workspace_id : null
  sensitive   = true
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of Log Analytics workspace (used for agent configuration)"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.zerotrust[0].primary_shared_key : null
  sensitive   = true
}

# Policy Outputs
output "policy_assignment_id" {
  description = "Resource ID of NSG enforcement policy assignment"
  value       = var.enforce_nsg_policy ? azurerm_resource_group_policy_assignment.nsg_enforcement[0].id : null
}

output "policy_definition_id" {
  description = "Resource ID of NSG requirement policy definition"
  value       = var.enforce_nsg_policy ? azurerm_policy_definition.require_nsg_on_subnet[0].id : null
}

# Subnet Outputs for VM deployment reference
output "spoke_subnet_ids" {
  description = "Resource IDs of spoke subnets for VM deployment"
  value = {
    for key, subnet in azurerm_subnet.spoke : key => subnet.id
  }
}

output "spoke_subnet_address_prefixes" {
  description = "Address prefixes of spoke subnets"
  value = {
    for key, subnet in azurerm_subnet.spoke : key => subnet.address_prefixes[0]
  }
}

# Connection Information for Azure Portal
output "bastion_connection_url" {
  description = "URL to access Azure Bastion through Azure Portal"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_bastion_host.zerotrust.id}/connect"
}

# Firewall Manager Information
output "firewall_manager_url" {
  description = "URL to manage Azure Firewall through Azure Portal"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_firewall_policy.zerotrust.id}/overview"
}

# Resource Summary
output "deployment_summary" {
  description = "Summary of deployed zero-trust infrastructure"
  value = {
    resource_group    = azurerm_resource_group.zerotrust.name
    hub_vnet         = azurerm_virtual_network.hub.name
    spoke_vnets      = [for vnet in azurerm_virtual_network.spoke : vnet.name]
    bastion_host     = azurerm_bastion_host.zerotrust.name
    firewall         = azurerm_firewall.zerotrust.name
    firewall_policy  = azurerm_firewall_policy.zerotrust.name
    nsg_count        = length(azurerm_network_security_group.spoke_workload)
    monitoring       = var.enable_diagnostic_settings ? "enabled" : "disabled"
    policies         = var.enforce_nsg_policy ? "enforced" : "not enforced"
  }
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, subject to change)"
  value = {
    bastion_standard     = var.bastion_sku == "Standard" ? "~$140" : "~$87"
    firewall_premium     = var.firewall_sku_tier == "Premium" ? "~$875" : "~$395"
    log_analytics        = var.enable_diagnostic_settings ? "~$2-50 (based on data ingestion)" : "$0"
    public_ips          = "~$7 (2 Standard Public IPs)"
    total_estimated     = var.firewall_sku_tier == "Premium" ? "~$1024+" : "~$539+"
    note               = "Costs vary by region and usage. See Azure pricing calculator for accurate estimates."
  }
}