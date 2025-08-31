# Output Values for Automated Server Patching Infrastructure
# This file defines output values to display important information after deployment

output "resource_group_name" {
  description = "Name of the resource group containing all patching demo resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "virtual_machine_name" {
  description = "Name of the Windows virtual machine configured for automated patching"
  value       = azurerm_windows_virtual_machine.main.name
}

output "virtual_machine_id" {
  description = "Resource ID of the virtual machine"
  value       = azurerm_windows_virtual_machine.main.id
}

output "virtual_machine_public_ip" {
  description = "Public IP address of the virtual machine for remote access"
  value       = azurerm_public_ip.main.ip_address
}

output "virtual_machine_private_ip" {
  description = "Private IP address of the virtual machine within the virtual network"
  value       = azurerm_network_interface.main.private_ip_address
}

output "virtual_machine_fqdn" {
  description = "Fully qualified domain name of the virtual machine (if configured)"
  value       = azurerm_public_ip.main.fqdn
}

output "admin_username" {
  description = "Administrator username for accessing the virtual machine"
  value       = azurerm_windows_virtual_machine.main.admin_username
}

output "maintenance_configuration_name" {
  description = "Name of the maintenance configuration for scheduled patching"
  value       = azurerm_maintenance_configuration.main.name
}

output "maintenance_configuration_id" {
  description = "Resource ID of the maintenance configuration"
  value       = azurerm_maintenance_configuration.main.id
}

output "maintenance_window_schedule" {
  description = "Configured maintenance window schedule information"
  value = {
    start_time  = var.maintenance_window_start_time
    duration    = "${var.maintenance_window_duration} hours"
    time_zone   = var.maintenance_window_time_zone
    recurrence  = var.maintenance_recurrence
    week_days   = var.maintenance_recurrence == "Week" ? var.maintenance_week_days : null
  }
}

output "patch_configuration" {
  description = "Windows patching configuration details"
  value = {
    classifications = var.patch_classifications
    reboot_setting = var.reboot_setting
    patch_mode     = azurerm_windows_virtual_machine.main.patch_mode
    assessment_mode = azurerm_windows_virtual_machine.main.patch_assessment_mode
  }
}

output "action_group_name" {
  description = "Name of the Action Group for patch deployment notifications"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "Resource ID of the Action Group"
  value       = azurerm_monitor_action_group.main.id
}

output "notification_email" {
  description = "Email address configured for patch deployment notifications"
  value       = var.notification_email
  sensitive   = true
}

output "activity_log_alerts" {
  description = "Names of configured activity log alerts for monitoring"
  value = {
    maintenance_config    = azurerm_monitor_activity_log_alert.maintenance_config.name
    maintenance_assignment = azurerm_monitor_activity_log_alert.maintenance_assignment.name
    vm_patch_operations   = azurerm_monitor_activity_log_alert.vm_patch_operations.name
  }
}

output "network_configuration" {
  description = "Network configuration details for the virtual machine"
  value = {
    virtual_network_name = azurerm_virtual_network.main.name
    subnet_name         = azurerm_subnet.main.name
    network_security_group = azurerm_network_security_group.main.name
    address_space       = azurerm_virtual_network.main.address_space
    subnet_prefix       = azurerm_subnet.main.address_prefixes
  }
}

output "resource_tags" {
  description = "Tags applied to all resources in this deployment"
  value       = local.common_tags
}

output "deployment_summary" {
  description = "Summary of the automated patching infrastructure deployment"
  value = {
    vm_name                    = azurerm_windows_virtual_machine.main.name
    vm_size                   = azurerm_windows_virtual_machine.main.size
    public_ip                 = azurerm_public_ip.main.ip_address
    maintenance_config        = azurerm_maintenance_configuration.main.name
    action_group             = azurerm_monitor_action_group.main.name
    notification_email       = var.notification_email
    location                 = azurerm_resource_group.main.location
    resource_group           = azurerm_resource_group.main.name
  }
  sensitive = true
}

# Validation outputs to confirm proper configuration
output "patch_management_validation" {
  description = "Validation information for patch management configuration"
  value = {
    vm_patch_mode_enabled               = azurerm_windows_virtual_machine.main.patch_mode == "AutomaticByPlatform"
    vm_assessment_mode_enabled          = azurerm_windows_virtual_machine.main.patch_assessment_mode == "AutomaticByPlatform"
    bypass_safety_checks_enabled       = azurerm_windows_virtual_machine.main.bypass_platform_safety_checks_on_user_schedule_enabled
    maintenance_assignment_created      = azurerm_maintenance_assignment_virtual_machine.main.id != ""
    action_group_configured            = length(azurerm_monitor_action_group.main.email_receiver) > 0
    activity_log_alerts_created        = length([
      azurerm_monitor_activity_log_alert.maintenance_config.id,
      azurerm_monitor_activity_log_alert.maintenance_assignment.id,
      azurerm_monitor_activity_log_alert.vm_patch_operations.id
    ]) == 3
  }
}

# CLI command outputs for manual verification
output "verification_commands" {
  description = "Azure CLI commands for verifying the deployment"
  value = {
    check_vm_patch_settings = "az vm show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_windows_virtual_machine.main.name} --query \"osProfile.windowsConfiguration.patchSettings\" --output table"
    check_maintenance_assignment = "az maintenance assignment list --resource-group ${azurerm_resource_group.main.name} --resource-name ${azurerm_windows_virtual_machine.main.name} --resource-type virtualMachines --provider-name Microsoft.Compute --output table"
    test_action_group = "az monitor action-group test-notifications create --resource-group ${azurerm_resource_group.main.name} --action-group-name ${azurerm_monitor_action_group.main.name} --notification-type Email --receivers ${azurerm_monitor_action_group.main.email_receiver[0].name}"
    assess_patches = "az vm assess-patches --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_windows_virtual_machine.main.name}"
  }
}