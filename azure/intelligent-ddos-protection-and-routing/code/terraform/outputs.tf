# Outputs for Azure Adaptive Network Security Infrastructure
# This file provides important resource information for verification and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all adaptive security resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the main resource group"
  value       = azurerm_resource_group.main.id
}

# Network Infrastructure Outputs
output "hub_vnet_name" {
  description = "Name of the hub virtual network"
  value       = azurerm_virtual_network.hub.name
}

output "hub_vnet_id" {
  description = "Resource ID of the hub virtual network"
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_address_space" {
  description = "Address space of the hub virtual network"
  value       = azurerm_virtual_network.hub.address_space
}

output "spoke_vnet_name" {
  description = "Name of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.name
}

output "spoke_vnet_id" {
  description = "Resource ID of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.id
}

output "spoke_vnet_address_space" {
  description = "Address space of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.address_space
}

# DDoS Protection Outputs
output "ddos_protection_plan_name" {
  description = "Name of the DDoS Protection Plan (if enabled)"
  value       = var.enable_ddos_protection ? azurerm_network_ddos_protection_plan.main[0].name : "DDoS Protection not enabled"
}

output "ddos_protection_plan_id" {
  description = "Resource ID of the DDoS Protection Plan (if enabled)"
  value       = var.enable_ddos_protection ? azurerm_network_ddos_protection_plan.main[0].id : null
}

output "ddos_protection_enabled" {
  description = "Whether DDoS Protection Standard is enabled"
  value       = var.enable_ddos_protection
}

# Azure Route Server Outputs
output "route_server_name" {
  description = "Name of the Azure Route Server"
  value       = azurerm_route_server.main.name
}

output "route_server_id" {
  description = "Resource ID of the Azure Route Server"
  value       = azurerm_route_server.main.id
}

output "route_server_public_ip" {
  description = "Public IP address of the Azure Route Server"
  value       = azurerm_public_ip.route_server.ip_address
}

output "route_server_private_ips" {
  description = "Private IP addresses of the Azure Route Server"
  value       = azurerm_route_server.main.virtual_router_ips
}

output "route_server_asn" {
  description = "ASN (Autonomous System Number) of the Azure Route Server"
  value       = azurerm_route_server.main.virtual_router_asn
}

# Azure Firewall Outputs
output "firewall_name" {
  description = "Name of the Azure Firewall"
  value       = azurerm_firewall.main.name
}

output "firewall_id" {
  description = "Resource ID of the Azure Firewall"
  value       = azurerm_firewall.main.id
}

output "firewall_public_ip" {
  description = "Public IP address of the Azure Firewall"
  value       = azurerm_public_ip.firewall.ip_address
}

output "firewall_private_ip" {
  description = "Private IP address of the Azure Firewall"
  value       = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

output "firewall_sku_tier" {
  description = "SKU tier of the Azure Firewall"
  value       = azurerm_firewall.main.sku_tier
}

# Subnet Information Outputs
output "route_server_subnet_id" {
  description = "Resource ID of the Route Server subnet"
  value       = azurerm_subnet.route_server.id
}

output "route_server_subnet_address_prefix" {
  description = "Address prefix of the Route Server subnet"
  value       = azurerm_subnet.route_server.address_prefixes[0]
}

output "firewall_subnet_id" {
  description = "Resource ID of the Azure Firewall subnet"
  value       = azurerm_subnet.firewall.id
}

output "firewall_subnet_address_prefix" {
  description = "Address prefix of the Azure Firewall subnet"
  value       = azurerm_subnet.firewall.address_prefixes[0]
}

output "application_subnet_id" {
  description = "Resource ID of the application subnet"
  value       = azurerm_subnet.application.id
}

output "application_subnet_address_prefix" {
  description = "Address prefix of the application subnet"
  value       = azurerm_subnet.application.address_prefixes[0]
}

output "database_subnet_id" {
  description = "Resource ID of the database subnet"
  value       = azurerm_subnet.database.id
}

output "database_subnet_address_prefix" {
  description = "Address prefix of the database subnet"
  value       = azurerm_subnet.database.address_prefixes[0]
}

# Monitoring and Logging Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
  sensitive   = true
}

output "storage_account_name" {
  description = "Name of the storage account for flow logs (if enabled)"
  value       = var.enable_flow_logs ? azurerm_storage_account.flow_logs[0].name : "Flow logs not enabled"
}

output "storage_account_id" {
  description = "Resource ID of the storage account for flow logs (if enabled)"
  value       = var.enable_flow_logs ? azurerm_storage_account.flow_logs[0].id : null
}

# Network Security Group Outputs
output "spoke_nsg_name" {
  description = "Name of the Network Security Group for spoke network"
  value       = azurerm_network_security_group.spoke.name
}

output "spoke_nsg_id" {
  description = "Resource ID of the Network Security Group for spoke network"
  value       = azurerm_network_security_group.spoke.id
}

# Network Watcher Outputs
output "network_watcher_name" {
  description = "Name of the Network Watcher (if enabled)"
  value       = var.enable_network_watcher ? azurerm_network_watcher.main[0].name : "Network Watcher not enabled"
}

output "network_watcher_id" {
  description = "Resource ID of the Network Watcher (if enabled)"
  value       = var.enable_network_watcher ? azurerm_network_watcher.main[0].id : null
}

# Flow Logs Outputs
output "flow_logs_enabled" {
  description = "Whether NSG flow logs are enabled"
  value       = var.enable_flow_logs
}

output "flow_logs_name" {
  description = "Name of the NSG flow logs (if enabled)"
  value       = var.enable_flow_logs && var.enable_network_watcher ? azurerm_network_watcher_flow_log.spoke[0].name : "Flow logs not enabled"
}

# Alert Configuration Outputs
output "action_group_name" {
  description = "Name of the action group for DDoS alerts (if enabled)"
  value       = var.enable_ddos_alerts ? azurerm_monitor_action_group.ddos_alerts[0].name : "DDoS alerts not enabled"
}

output "action_group_id" {
  description = "Resource ID of the action group for DDoS alerts (if enabled)"
  value       = var.enable_ddos_alerts ? azurerm_monitor_action_group.ddos_alerts[0].id : null
}

output "ddos_attack_alert_name" {
  description = "Name of the DDoS attack detection alert (if enabled)"
  value       = var.enable_ddos_alerts && var.enable_ddos_protection ? azurerm_monitor_metric_alert.ddos_attack[0].name : "DDoS attack alert not enabled"
}

output "high_traffic_alert_name" {
  description = "Name of the high traffic volume alert (if enabled)"
  value       = var.enable_ddos_alerts && var.enable_ddos_protection ? azurerm_monitor_metric_alert.high_traffic[0].name : "High traffic alert not enabled"
}

# Public IP Outputs
output "route_server_public_ip_address" {
  description = "Public IP address assigned to Azure Route Server"
  value       = azurerm_public_ip.route_server.ip_address
}

output "firewall_public_ip_address" {
  description = "Public IP address assigned to Azure Firewall"
  value       = azurerm_public_ip.firewall.ip_address
}

output "route_server_public_ip_fqdn" {
  description = "FQDN of the Route Server public IP (if configured)"
  value       = azurerm_public_ip.route_server.fqdn
}

output "firewall_public_ip_fqdn" {
  description = "FQDN of the Firewall public IP (if configured)"
  value       = azurerm_public_ip.firewall.fqdn
}

# Peering Status Outputs
output "hub_to_spoke_peering_status" {
  description = "Status of VNet peering from hub to spoke"
  value       = azurerm_virtual_network_peering.hub_to_spoke.peering_state
}

output "spoke_to_hub_peering_status" {
  description = "Status of VNet peering from spoke to hub"
  value       = azurerm_virtual_network_peering.spoke_to_hub.peering_state
}

# Configuration Summary Outputs
output "deployment_summary" {
  description = "Summary of deployed adaptive network security components"
  value = {
    ddos_protection_enabled  = var.enable_ddos_protection
    route_server_deployed   = true
    firewall_deployed       = true
    monitoring_enabled      = true
    flow_logs_enabled       = var.enable_flow_logs
    network_watcher_enabled = var.enable_network_watcher
    alerts_configured       = var.enable_ddos_alerts
    vnets_peered           = true
  }
}

# Resource Count Outputs
output "resource_counts" {
  description = "Count of major resources deployed"
  value = {
    virtual_networks     = 2
    subnets             = 5
    public_ips          = 2
    network_security_groups = 1
    ddos_protection_plans = var.enable_ddos_protection ? 1 : 0
    route_servers       = 1
    firewalls          = 1
    log_analytics_workspaces = 1
    storage_accounts    = var.enable_flow_logs ? 1 : 0
    action_groups       = var.enable_ddos_alerts ? 1 : 0
    metric_alerts       = var.enable_ddos_alerts && var.enable_ddos_protection ? 2 : 0
  }
}

# Cost Estimation Guidance
output "cost_estimation_notes" {
  description = "Notes for estimating monthly costs of deployed resources"
  value = {
    ddos_protection = var.enable_ddos_protection ? "DDoS Protection Standard: Fixed monthly fee plus per-protected public IP" : "Not enabled"
    route_server = "Azure Route Server: Fixed monthly fee per deployment"
    firewall = "Azure Firewall: Fixed monthly fee plus data processing charges"
    log_analytics = "Log Analytics: Pay-per-GB ingestion and retention"
    storage = var.enable_flow_logs ? "Storage Account: Pay-per-GB storage and transaction costs" : "Not enabled"
    network_costs = "VNet peering, public IP addresses, and data transfer charges apply"
  }
}

# Next Steps and Configuration Guidance
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Configure BGP peering with network virtual appliances on Route Server",
    "Customize Azure Firewall rules based on your application requirements",
    "Set up custom alert recipients by providing email addresses in variables",
    "Review and tune DDoS Protection policies based on traffic patterns",
    "Configure additional network security groups for granular access control",
    "Set up automated response playbooks for security incidents",
    "Test network connectivity and routing between hub and spoke networks"
  ]
}