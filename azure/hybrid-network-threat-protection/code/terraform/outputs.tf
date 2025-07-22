# Outputs for Azure Hybrid Network Security Infrastructure
# This file defines all output values for the hybrid network security solution

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Virtual Network Information
output "hub_virtual_network_name" {
  description = "Name of the hub virtual network"
  value       = azurerm_virtual_network.hub.name
}

output "hub_virtual_network_id" {
  description = "Resource ID of the hub virtual network"
  value       = azurerm_virtual_network.hub.id
}

output "hub_virtual_network_address_space" {
  description = "Address space of the hub virtual network"
  value       = azurerm_virtual_network.hub.address_space
}

output "spoke_virtual_network_name" {
  description = "Name of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.name
}

output "spoke_virtual_network_id" {
  description = "Resource ID of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.id
}

output "spoke_virtual_network_address_space" {
  description = "Address space of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.address_space
}

# Subnet Information
output "firewall_subnet_id" {
  description = "Resource ID of the Azure Firewall subnet"
  value       = azurerm_subnet.firewall.id
}

output "gateway_subnet_id" {
  description = "Resource ID of the Gateway subnet"
  value       = azurerm_subnet.gateway.id
}

output "workload_subnet_id" {
  description = "Resource ID of the workload subnet"
  value       = azurerm_subnet.workload.id
}

output "workload_subnet_address_prefix" {
  description = "Address prefix of the workload subnet"
  value       = azurerm_subnet.workload.address_prefixes[0]
}

# Azure Firewall Information
output "firewall_name" {
  description = "Name of the Azure Firewall"
  value       = azurerm_firewall.main.name
}

output "firewall_id" {
  description = "Resource ID of the Azure Firewall"
  value       = azurerm_firewall.main.id
}

output "firewall_private_ip_address" {
  description = "Private IP address of the Azure Firewall"
  value       = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

output "firewall_public_ip_address" {
  description = "Public IP address of the Azure Firewall"
  value       = azurerm_public_ip.firewall.ip_address
}

output "firewall_public_ip_fqdn" {
  description = "FQDN of the Azure Firewall public IP"
  value       = azurerm_public_ip.firewall.fqdn
}

output "firewall_sku_tier" {
  description = "SKU tier of the Azure Firewall"
  value       = azurerm_firewall.main.sku_tier
}

# Azure Firewall Policy Information
output "firewall_policy_name" {
  description = "Name of the Azure Firewall policy"
  value       = azurerm_firewall_policy.main.name
}

output "firewall_policy_id" {
  description = "Resource ID of the Azure Firewall policy"
  value       = azurerm_firewall_policy.main.id
}

output "firewall_policy_threat_intel_mode" {
  description = "Threat intelligence mode of the Azure Firewall policy"
  value       = azurerm_firewall_policy.main.threat_intelligence_mode
}

# ExpressRoute Gateway Information
output "expressroute_gateway_name" {
  description = "Name of the ExpressRoute Gateway"
  value       = azurerm_virtual_network_gateway.expressroute.name
}

output "expressroute_gateway_id" {
  description = "Resource ID of the ExpressRoute Gateway"
  value       = azurerm_virtual_network_gateway.expressroute.id
}

output "expressroute_gateway_public_ip_address" {
  description = "Public IP address of the ExpressRoute Gateway"
  value       = azurerm_public_ip.expressroute_gateway.ip_address
}

output "expressroute_gateway_sku" {
  description = "SKU of the ExpressRoute Gateway"
  value       = azurerm_virtual_network_gateway.expressroute.sku
}

# ExpressRoute Connection Information
output "expressroute_connection_name" {
  description = "Name of the ExpressRoute connection (if created)"
  value       = var.create_expressroute_connection && var.expressroute_circuit_resource_id != "" ? azurerm_virtual_network_gateway_connection.expressroute[0].name : null
}

output "expressroute_connection_id" {
  description = "Resource ID of the ExpressRoute connection (if created)"
  value       = var.create_expressroute_connection && var.expressroute_circuit_resource_id != "" ? azurerm_virtual_network_gateway_connection.expressroute[0].id : null
}

# Route Table Information
output "spoke_route_table_name" {
  description = "Name of the spoke route table"
  value       = azurerm_route_table.spoke.name
}

output "spoke_route_table_id" {
  description = "Resource ID of the spoke route table"
  value       = azurerm_route_table.spoke.id
}

# Network Security Group Information
output "workload_nsg_name" {
  description = "Name of the workload network security group"
  value       = azurerm_network_security_group.workload.name
}

output "workload_nsg_id" {
  description = "Resource ID of the workload network security group"
  value       = azurerm_network_security_group.workload.id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Public IP Addresses
output "public_ip_addresses" {
  description = "Map of all public IP addresses created"
  value = {
    firewall            = azurerm_public_ip.firewall.ip_address
    firewall_management = var.enable_forced_tunneling ? azurerm_public_ip.firewall_management[0].ip_address : null
    expressroute_gateway = azurerm_public_ip.expressroute_gateway.ip_address
  }
}

# Network Configuration Summary
output "network_configuration_summary" {
  description = "Summary of network configuration"
  value = {
    hub_vnet_address_space    = var.hub_vnet_address_space
    spoke_vnet_address_space  = var.spoke_vnet_address_space
    firewall_subnet_prefix    = var.firewall_subnet_address_prefix
    gateway_subnet_prefix     = var.gateway_subnet_address_prefix
    workload_subnet_prefix    = var.workload_subnet_address_prefix
    on_premises_address_space = var.on_premises_address_space
  }
}

# Security Configuration Summary
output "security_configuration_summary" {
  description = "Summary of security configuration"
  value = {
    firewall_sku_tier            = var.firewall_sku_tier
    firewall_threat_intel_mode   = var.firewall_threat_intel_mode
    firewall_idps_mode          = var.firewall_idps_mode
    firewall_dns_proxy_enabled  = var.firewall_dns_proxy_enabled
    diagnostic_logs_enabled     = var.enable_diagnostic_logs
    forced_tunneling_enabled    = var.enable_forced_tunneling
  }
}

# Monitoring and Logging Configuration
output "monitoring_configuration" {
  description = "Configuration details for monitoring and logging"
  value = {
    log_analytics_workspace_name = azurerm_log_analytics_workspace.main.name
    log_analytics_retention_days = var.log_analytics_retention_days
    log_analytics_sku           = var.log_analytics_sku
    diagnostic_log_categories   = var.diagnostic_log_categories
    diagnostic_logs_enabled     = var.enable_diagnostic_logs
  }
}

# Azure Firewall Rules Configuration
output "firewall_rules_configuration" {
  description = "Configuration details for Azure Firewall rules"
  value = {
    allowed_web_fqdns     = var.allowed_web_fqdns
    allowed_ports         = var.allowed_ports
    network_rules_enabled = true
    application_rules_enabled = true
  }
}

# Deployment Information
output "deployment_information" {
  description = "Information about the deployment"
  value = {
    resource_prefix           = var.resource_prefix
    random_suffix            = random_string.suffix.result
    deployment_location      = var.location
    environment              = var.environment
    terraform_version        = ">= 1.0"
    azurerm_provider_version = "~> 3.0"
    deployment_timestamp     = timestamp()
  }
}

# Cost Management Information
output "cost_management_tags" {
  description = "Tags applied to resources for cost management"
  value       = var.tags
}

# Next Steps Information
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    expressroute_connection_command = var.expressroute_circuit_resource_id != "" && !var.create_expressroute_connection ? "Set create_expressroute_connection = true and run terraform apply to create ExpressRoute connection" : null
    monitoring_dashboard_url        = "https://portal.azure.com/#blade/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/logs"
    firewall_logs_query            = "AzureDiagnostics | where Category == 'AzureFirewallNetworkRule' | take 10"
    threat_intel_logs_query        = "AzureDiagnostics | where Category == 'AZFWThreatIntel' | take 10"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_firewall_status = "az network firewall show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_firewall.main.name} --query 'provisioningState'"
    check_gateway_status  = "az network vnet-gateway show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_virtual_network_gateway.expressroute.name} --query 'provisioningState'"
    check_firewall_rules  = "az network firewall policy show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_firewall_policy.main.name}"
    check_route_table     = "az network route-table show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_route_table.spoke.name}"
  }
}