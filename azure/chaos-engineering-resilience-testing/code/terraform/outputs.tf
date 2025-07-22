# Output Values for Azure Chaos Studio and Application Insights Recipe
# This file defines outputs that provide important information after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.chaos_testing.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.chaos_testing.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.chaos_testing.id
}

# Log Analytics and Application Insights Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.chaos_workspace.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.chaos_workspace.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (GUID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.chaos_workspace.workspace_id
}

output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = azurerm_application_insights.chaos_insights.name
}

output "application_insights_id" {
  description = "ID of the Application Insights component"
  value       = azurerm_application_insights.chaos_insights.id
}

output "application_insights_app_id" {
  description = "Application ID of the Application Insights component"
  value       = azurerm_application_insights.chaos_insights.app_id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.chaos_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.chaos_insights.connection_string
  sensitive   = true
}

# Networking Information
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.chaos_vnet.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.chaos_vnet.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = azurerm_subnet.chaos_subnet.name
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = azurerm_subnet.chaos_subnet.id
}

output "network_security_group_name" {
  description = "Name of the network security group"
  value       = azurerm_network_security_group.chaos_nsg.name
}

output "network_security_group_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.chaos_nsg.id
}

# Virtual Machine Information
output "vm_name" {
  description = "Name of the virtual machine"
  value       = azurerm_linux_virtual_machine.chaos_vm.name
}

output "vm_id" {
  description = "ID of the virtual machine"
  value       = azurerm_linux_virtual_machine.chaos_vm.id
}

output "vm_size" {
  description = "Size of the virtual machine"
  value       = azurerm_linux_virtual_machine.chaos_vm.size
}

output "vm_admin_username" {
  description = "Administrator username for the virtual machine"
  value       = azurerm_linux_virtual_machine.chaos_vm.admin_username
}

output "vm_public_ip_address" {
  description = "Public IP address of the virtual machine"
  value       = azurerm_public_ip.chaos_vm_pip.ip_address
}

output "vm_private_ip_address" {
  description = "Private IP address of the virtual machine"
  value       = azurerm_network_interface.chaos_vm_nic.private_ip_address
}

output "vm_ssh_connection_command" {
  description = "SSH command to connect to the virtual machine"
  value       = "ssh ${azurerm_linux_virtual_machine.chaos_vm.admin_username}@${azurerm_public_ip.chaos_vm_pip.ip_address}"
}

# Chaos Studio Information
output "managed_identity_name" {
  description = "Name of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.chaos_identity.name
}

output "managed_identity_id" {
  description = "ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.chaos_identity.id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.chaos_identity.principal_id
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.chaos_identity.client_id
}

output "chaos_vm_target_id" {
  description = "ID of the Chaos Studio VM target"
  value       = azapi_resource.chaos_vm_target.id
}

output "chaos_experiment_name" {
  description = "Name of the chaos experiment (if enabled)"
  value       = var.chaos_experiment_enabled ? azapi_resource.chaos_experiment[0].name : null
}

output "chaos_experiment_id" {
  description = "ID of the chaos experiment (if enabled)"
  value       = var.chaos_experiment_enabled ? azapi_resource.chaos_experiment[0].id : null
}

# Monitoring and Alerting Information
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = azurerm_monitor_action_group.chaos_alerts.name
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = azurerm_monitor_action_group.chaos_alerts.id
}

output "cpu_alert_rule_name" {
  description = "Name of the CPU alert rule"
  value       = azurerm_monitor_metric_alert.chaos_cpu_alert.name
}

output "cpu_alert_rule_id" {
  description = "ID of the CPU alert rule"
  value       = azurerm_monitor_metric_alert.chaos_cpu_alert.id
}

# Useful Commands for Testing
output "chaos_experiment_start_command" {
  description = "Azure CLI command to start the chaos experiment"
  value = var.chaos_experiment_enabled ? "az rest --method post --url 'https://management.azure.com${azapi_resource.chaos_experiment[0].id}/start?api-version=2024-01-01'" : "Chaos experiment not enabled"
}

output "chaos_experiment_stop_command" {
  description = "Azure CLI command to stop the chaos experiment"
  value = var.chaos_experiment_enabled ? "az rest --method post --url 'https://management.azure.com${azapi_resource.chaos_experiment[0].id}/stop?api-version=2024-01-01'" : "Chaos experiment not enabled"
}

output "application_insights_query_command" {
  description = "Azure CLI command to query Application Insights for chaos events"
  value = "az monitor app-insights query --app ${azurerm_application_insights.chaos_insights.name} --resource-group ${azurerm_resource_group.chaos_testing.name} --analytics-query \"customEvents | where name contains 'Chaos' | project timestamp, name, customDimensions | order by timestamp desc | take 10\""
}

output "vm_status_check_command" {
  description = "Azure CLI command to check VM status"
  value = "az vm get-instance-view --name ${azurerm_linux_virtual_machine.chaos_vm.name} --resource-group ${azurerm_resource_group.chaos_testing.name} --query instanceView.statuses[1].displayStatus --output tsv"
}

# Quick Reference Information
output "quick_reference" {
  description = "Quick reference information for using the deployed infrastructure"
  value = {
    resource_group                   = azurerm_resource_group.chaos_testing.name
    vm_name                         = azurerm_linux_virtual_machine.chaos_vm.name
    vm_public_ip                    = azurerm_public_ip.chaos_vm_pip.ip_address
    application_insights_name       = azurerm_application_insights.chaos_insights.name
    chaos_experiment_enabled        = var.chaos_experiment_enabled
    chaos_experiment_name           = var.chaos_experiment_enabled ? azapi_resource.chaos_experiment[0].name : "Not created"
    log_analytics_workspace_name   = azurerm_log_analytics_workspace.chaos_workspace.name
    action_group_name              = azurerm_monitor_action_group.chaos_alerts.name
  }
}