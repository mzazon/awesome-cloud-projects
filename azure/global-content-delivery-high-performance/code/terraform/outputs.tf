# Output values for Azure Front Door Premium and Azure NetApp Files deployment

# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Network Outputs
output "virtual_network_primary_id" {
  description = "ID of the primary virtual network"
  value       = azurerm_virtual_network.primary.id
}

output "virtual_network_secondary_id" {
  description = "ID of the secondary virtual network"
  value       = azurerm_virtual_network.secondary.id
}

output "anf_subnet_primary_id" {
  description = "ID of the Azure NetApp Files subnet in primary region"
  value       = azurerm_subnet.anf_primary.id
}

output "anf_subnet_secondary_id" {
  description = "ID of the Azure NetApp Files subnet in secondary region"
  value       = azurerm_subnet.anf_secondary.id
}

output "private_endpoint_subnet_primary_id" {
  description = "ID of the private endpoint subnet in primary region"
  value       = azurerm_subnet.pe_primary.id
}

output "private_endpoint_subnet_secondary_id" {
  description = "ID of the private endpoint subnet in secondary region"
  value       = azurerm_subnet.pe_secondary.id
}

# Azure NetApp Files Outputs
output "netapp_account_primary_id" {
  description = "ID of the Azure NetApp Files account in primary region"
  value       = azurerm_netapp_account.primary.id
}

output "netapp_account_secondary_id" {
  description = "ID of the Azure NetApp Files account in secondary region"
  value       = azurerm_netapp_account.secondary.id
}

output "netapp_account_primary_name" {
  description = "Name of the Azure NetApp Files account in primary region"
  value       = azurerm_netapp_account.primary.name
}

output "netapp_account_secondary_name" {
  description = "Name of the Azure NetApp Files account in secondary region"
  value       = azurerm_netapp_account.secondary.name
}

output "netapp_capacity_pool_primary_id" {
  description = "ID of the Azure NetApp Files capacity pool in primary region"
  value       = azurerm_netapp_pool.primary.id
}

output "netapp_capacity_pool_secondary_id" {
  description = "ID of the Azure NetApp Files capacity pool in secondary region"
  value       = azurerm_netapp_pool.secondary.id
}

output "netapp_volume_primary_id" {
  description = "ID of the Azure NetApp Files volume in primary region"
  value       = azurerm_netapp_volume.primary.id
}

output "netapp_volume_secondary_id" {
  description = "ID of the Azure NetApp Files volume in secondary region"
  value       = azurerm_netapp_volume.secondary.id
}

output "netapp_volume_primary_mount_ip" {
  description = "Mount IP address for the Azure NetApp Files volume in primary region"
  value       = azurerm_netapp_volume.primary.mount_ip_addresses[0]
}

output "netapp_volume_secondary_mount_ip" {
  description = "Mount IP address for the Azure NetApp Files volume in secondary region"
  value       = azurerm_netapp_volume.secondary.mount_ip_addresses[0]
}

output "netapp_volume_primary_mount_path" {
  description = "Mount path for the Azure NetApp Files volume in primary region"
  value       = "/${azurerm_netapp_volume.primary.volume_path}"
}

output "netapp_volume_secondary_mount_path" {
  description = "Mount path for the Azure NetApp Files volume in secondary region"
  value       = "/${azurerm_netapp_volume.secondary.volume_path}"
}

# Load Balancer Outputs
output "load_balancer_primary_id" {
  description = "ID of the load balancer in primary region"
  value       = azurerm_lb.primary.id
}

output "load_balancer_secondary_id" {
  description = "ID of the load balancer in secondary region"
  value       = azurerm_lb.secondary.id
}

output "load_balancer_primary_private_ip" {
  description = "Private IP address of the load balancer in primary region"
  value       = azurerm_lb.primary.frontend_ip_configuration[0].private_ip_address
}

output "load_balancer_secondary_private_ip" {
  description = "Private IP address of the load balancer in secondary region"
  value       = azurerm_lb.secondary.frontend_ip_configuration[0].private_ip_address
}

# Azure Front Door Outputs
output "front_door_profile_id" {
  description = "ID of the Azure Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.main.id
}

output "front_door_profile_name" {
  description = "Name of the Azure Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.main.name
}

output "front_door_endpoint_id" {
  description = "ID of the Azure Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.main.id
}

output "front_door_endpoint_hostname" {
  description = "Hostname of the Azure Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.main.host_name
}

output "front_door_endpoint_url" {
  description = "Full URL of the Azure Front Door endpoint"
  value       = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
}

output "front_door_origin_group_id" {
  description = "ID of the Azure Front Door origin group"
  value       = azurerm_cdn_frontdoor_origin_group.main.id
}

output "front_door_primary_origin_id" {
  description = "ID of the primary Azure Front Door origin"
  value       = azurerm_cdn_frontdoor_origin.primary.id
}

output "front_door_secondary_origin_id" {
  description = "ID of the secondary Azure Front Door origin"
  value       = azurerm_cdn_frontdoor_origin.secondary.id
}

output "front_door_route_id" {
  description = "ID of the Azure Front Door route"
  value       = azurerm_cdn_frontdoor_route.main.id
}

# WAF Policy Outputs
output "waf_policy_id" {
  description = "ID of the WAF policy"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.id
}

output "waf_policy_name" {
  description = "Name of the WAF policy"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.name
}

output "waf_policy_mode" {
  description = "Mode of the WAF policy"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.mode
}

# Monitoring Outputs
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Alert Rules Outputs
output "high_request_count_alert_id" {
  description = "ID of the high request count alert rule"
  value       = azurerm_monitor_metric_alert.high_request_count.id
}

output "high_response_time_alert_id" {
  description = "ID of the high response time alert rule"
  value       = azurerm_monitor_metric_alert.high_response_time.id
}

# Diagnostic Settings Outputs
output "front_door_diagnostic_setting_id" {
  description = "ID of the Front Door diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.front_door.id
}

output "netapp_primary_diagnostic_setting_id" {
  description = "ID of the NetApp primary diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.netapp_primary.id
}

output "netapp_secondary_diagnostic_setting_id" {
  description = "ID of the NetApp secondary diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.netapp_secondary.id
}

# Summary Information
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    resource_group_name           = azurerm_resource_group.main.name
    front_door_endpoint_url       = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
    primary_region               = var.location_primary
    secondary_region             = var.location_secondary
    netapp_service_level         = var.anf_service_level
    netapp_volume_size_gb        = var.anf_volume_size
    front_door_sku               = var.front_door_sku
    waf_mode                     = var.waf_mode
    monitoring_enabled           = true
    private_link_enabled         = true
  }
}

# Connection Information
output "connection_information" {
  description = "Information needed to connect to the deployed resources"
  value = {
    front_door_endpoint         = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
    netapp_volume_primary_mount = "${azurerm_netapp_volume.primary.mount_ip_addresses[0]}:/${azurerm_netapp_volume.primary.volume_path}"
    netapp_volume_secondary_mount = "${azurerm_netapp_volume.secondary.mount_ip_addresses[0]}:/${azurerm_netapp_volume.secondary.volume_path}"
    load_balancer_primary_ip    = azurerm_lb.primary.frontend_ip_configuration[0].private_ip_address
    load_balancer_secondary_ip  = azurerm_lb.secondary.frontend_ip_configuration[0].private_ip_address
    log_analytics_workspace_id  = azurerm_log_analytics_workspace.main.workspace_id
  }
}

# Cost Information
output "cost_information" {
  description = "Information about the cost factors of the deployment"
  value = {
    front_door_sku               = var.front_door_sku
    netapp_capacity_pool_size_tb = var.anf_capacity_pool_size
    netapp_service_level         = var.anf_service_level
    netapp_volume_size_gb        = var.anf_volume_size
    log_analytics_sku            = var.log_analytics_sku
    regions                      = [var.location_primary, var.location_secondary]
    cost_optimization_note       = "Review Azure Pricing Calculator for detailed cost estimates"
  }
}