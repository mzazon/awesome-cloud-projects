# Outputs for Azure Infrastructure Lifecycle Management
# This file defines all output values that will be displayed after deployment

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources were deployed"
  value       = azurerm_resource_group.main.location
}

# Virtual Network Outputs
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "subnet_id" {
  description = "ID of the web subnet"
  value       = azurerm_subnet.web.id
}

# Load Balancer Outputs
output "load_balancer_public_ip" {
  description = "Public IP address of the load balancer"
  value       = azurerm_public_ip.lb.ip_address
}

output "load_balancer_fqdn" {
  description = "Fully qualified domain name of the load balancer"
  value       = azurerm_public_ip.lb.fqdn
}

output "load_balancer_id" {
  description = "ID of the load balancer"
  value       = azurerm_lb.main.id
}

# Virtual Machine Scale Set Outputs
output "vmss_name" {
  description = "Name of the virtual machine scale set"
  value       = azurerm_linux_virtual_machine_scale_set.main.name
}

output "vmss_id" {
  description = "ID of the virtual machine scale set"
  value       = azurerm_linux_virtual_machine_scale_set.main.id
}

output "vmss_principal_id" {
  description = "Principal ID of the virtual machine scale set managed identity"
  value       = azurerm_linux_virtual_machine_scale_set.main.identity[0].principal_id
}

output "vmss_instances" {
  description = "Number of instances in the virtual machine scale set"
  value       = azurerm_linux_virtual_machine_scale_set.main.instances
}

# Maintenance Configuration Outputs
output "maintenance_configuration_name" {
  description = "Name of the maintenance configuration"
  value       = azurerm_maintenance_configuration.main.name
}

output "maintenance_configuration_id" {
  description = "ID of the maintenance configuration"
  value       = azurerm_maintenance_configuration.main.id
}

output "maintenance_window_start_time" {
  description = "Start time of the maintenance window"
  value       = var.maintenance_window_start_time
}

output "maintenance_window_duration" {
  description = "Duration of the maintenance window"
  value       = var.maintenance_window_duration
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if monitoring is enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if monitoring is enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_key" {
  description = "Primary shared key of the Log Analytics workspace (if monitoring is enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].primary_shared_key : null
  sensitive   = true
}

# Policy Outputs
output "policy_definition_id" {
  description = "ID of the deployment stack governance policy definition"
  value       = azurerm_policy_definition.deployment_stack_governance.id
}

output "policy_assignment_id" {
  description = "ID of the policy assignment"
  value       = azurerm_resource_group_policy_assignment.deployment_stack_governance.id
}

# Deployment Stack Outputs
output "deployment_stack_name" {
  description = "Name of the deployment stack (if enabled)"
  value       = var.enable_deployment_stack_protection ? azapi_resource.deployment_stack[0].name : null
}

output "deployment_stack_id" {
  description = "ID of the deployment stack (if enabled)"
  value       = var.enable_deployment_stack_protection ? azapi_resource.deployment_stack[0].id : null
}

# Auto Scaling Outputs
output "autoscale_setting_id" {
  description = "ID of the autoscale setting (if auto-scaling is enabled)"
  value       = var.enable_auto_scale ? azurerm_monitor_autoscale_setting.main[0].id : null
}

output "min_capacity" {
  description = "Minimum capacity for auto-scaling (if enabled)"
  value       = var.enable_auto_scale ? var.min_capacity : null
}

output "max_capacity" {
  description = "Maximum capacity for auto-scaling (if enabled)"
  value       = var.enable_auto_scale ? var.max_capacity : null
}

# Security Outputs
output "network_security_group_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.web.id
}

output "network_security_group_name" {
  description = "Name of the network security group"
  value       = azurerm_network_security_group.web.name
}

# Resource Identifiers for Management
output "all_resource_ids" {
  description = "List of all created resource IDs for management purposes"
  value = [
    azurerm_resource_group.main.id,
    azurerm_virtual_network.main.id,
    azurerm_subnet.web.id,
    azurerm_network_security_group.web.id,
    azurerm_public_ip.lb.id,
    azurerm_lb.main.id,
    azurerm_linux_virtual_machine_scale_set.main.id,
    azurerm_maintenance_configuration.main.id,
    azurerm_policy_definition.deployment_stack_governance.id,
    azurerm_resource_group_policy_assignment.deployment_stack_governance.id
  ]
}

# Connection Information
output "web_application_url" {
  description = "URL to access the web application"
  value       = "http://${azurerm_public_ip.lb.ip_address}"
}

output "ssh_connection_command" {
  description = "Example SSH command to connect to VMSS instances (requires bastion or VPN)"
  value       = "Note: Direct SSH access requires bastion host or VPN connection to private subnet"
}

# Compliance and Governance
output "compliance_dashboard_url" {
  description = "URL to access the compliance dashboard (if monitoring is enabled)"
  value       = var.enable_monitoring ? "https://portal.azure.com/#@/resource${azapi_resource.monitoring_workbook[0].id}/overview" : null
}

output "azure_update_manager_url" {
  description = "URL to access Azure Update Manager for this resource group"
  value       = "https://portal.azure.com/#@/resource${azurerm_resource_group.main.id}/overview"
}

# Environment Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}

# Random Suffix
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}