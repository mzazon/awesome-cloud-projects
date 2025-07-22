# ==============================================================================
# MSP TENANT OUTPUTS
# ==============================================================================

output "msp_resource_group_name" {
  description = "Name of the MSP resource group"
  value       = azurerm_resource_group.msp_management.name
}

output "msp_resource_group_id" {
  description = "ID of the MSP resource group"
  value       = azurerm_resource_group.msp_management.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.lighthouse_monitoring.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.lighthouse_monitoring.id
}

output "log_analytics_workspace_resource_id" {
  description = "Full resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.lighthouse_monitoring.id
}

output "automanage_configuration_name" {
  description = "Name of the Azure Automanage configuration profile"
  value       = azurerm_automanage_configuration.lighthouse_profile.name
}

output "automanage_configuration_id" {
  description = "ID of the Azure Automanage configuration profile"
  value       = azurerm_automanage_configuration.lighthouse_profile.id
}

output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = azurerm_monitor_action_group.lighthouse_alerts.name
}

output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = azurerm_monitor_action_group.lighthouse_alerts.id
}

# ==============================================================================
# AZURE LIGHTHOUSE OUTPUTS
# ==============================================================================

output "lighthouse_definition_name" {
  description = "Name of the Azure Lighthouse definition"
  value       = azurerm_lighthouse_definition.cross_tenant_governance.name
}

output "lighthouse_definition_id" {
  description = "ID of the Azure Lighthouse definition"
  value       = azurerm_lighthouse_definition.cross_tenant_governance.id
}

output "lighthouse_assignment_id" {
  description = "ID of the Azure Lighthouse assignment"
  value       = azurerm_lighthouse_assignment.cross_tenant_governance.id
}

output "lighthouse_assignment_scope" {
  description = "Scope of the Azure Lighthouse assignment"
  value       = azurerm_lighthouse_assignment.cross_tenant_governance.scope
}

output "managing_tenant_id" {
  description = "ID of the managing tenant (MSP)"
  value       = var.msp_tenant_id
}

output "managed_tenant_id" {
  description = "ID of the managed tenant (Customer)"
  value       = var.customer_tenant_id
}

# ==============================================================================
# CUSTOMER TENANT OUTPUTS
# ==============================================================================

output "customer_resource_group_name" {
  description = "Name of the customer resource group"
  value       = azurerm_resource_group.customer_workloads.name
}

output "customer_resource_group_id" {
  description = "ID of the customer resource group"
  value       = azurerm_resource_group.customer_workloads.id
}

output "customer_virtual_network_name" {
  description = "Name of the customer virtual network"
  value       = azurerm_virtual_network.customer_vnet.name
}

output "customer_virtual_network_id" {
  description = "ID of the customer virtual network"
  value       = azurerm_virtual_network.customer_vnet.id
}

output "customer_subnet_name" {
  description = "Name of the customer subnet"
  value       = azurerm_subnet.customer_subnet.name
}

output "customer_subnet_id" {
  description = "ID of the customer subnet"
  value       = azurerm_subnet.customer_subnet.id
}

output "customer_vm_name" {
  description = "Name of the customer virtual machine"
  value       = azurerm_windows_virtual_machine.customer_vm.name
}

output "customer_vm_id" {
  description = "ID of the customer virtual machine"
  value       = azurerm_windows_virtual_machine.customer_vm.id
}

output "customer_vm_private_ip" {
  description = "Private IP address of the customer virtual machine"
  value       = azurerm_windows_virtual_machine.customer_vm.private_ip_address
}

output "customer_vm_public_ip" {
  description = "Public IP address of the customer virtual machine"
  value       = azurerm_public_ip.customer_vm_pip.ip_address
}

output "customer_vm_fqdn" {
  description = "Fully qualified domain name of the customer virtual machine"
  value       = azurerm_public_ip.customer_vm_pip.fqdn
}

output "customer_vm_size" {
  description = "Size of the customer virtual machine"
  value       = azurerm_windows_virtual_machine.customer_vm.size
}

output "customer_vm_admin_username" {
  description = "Administrator username for the customer virtual machine"
  value       = azurerm_windows_virtual_machine.customer_vm.admin_username
}

output "customer_nsg_name" {
  description = "Name of the customer network security group"
  value       = azurerm_network_security_group.customer_nsg.name
}

output "customer_nsg_id" {
  description = "ID of the customer network security group"
  value       = azurerm_network_security_group.customer_nsg.id
}

# ==============================================================================
# AUTOMANAGE OUTPUTS
# ==============================================================================

output "automanage_assignment_id" {
  description = "ID of the Azure Automanage configuration assignment"
  value       = azurerm_automanage_configuration_assignment.customer_vm_automanage.id
}

output "automanage_assignment_status" {
  description = "Status of the Azure Automanage configuration assignment"
  value       = "Assigned to ${azurerm_windows_virtual_machine.customer_vm.name}"
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

output "vm_availability_alert_name" {
  description = "Name of the VM availability alert rule"
  value       = azurerm_monitor_metric_alert.vm_availability.name
}

output "vm_availability_alert_id" {
  description = "ID of the VM availability alert rule"
  value       = azurerm_monitor_metric_alert.vm_availability.id
}

output "vm_heartbeat_alert_name" {
  description = "Name of the VM heartbeat alert rule"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.vm_heartbeat.name
}

output "vm_heartbeat_alert_id" {
  description = "ID of the VM heartbeat alert rule"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.vm_heartbeat.id
}

output "vm_diagnostic_setting_name" {
  description = "Name of the VM diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.customer_vm_diagnostics.name
}

output "nsg_diagnostic_setting_name" {
  description = "Name of the NSG diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.customer_nsg_diagnostics.name
}

# ==============================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# ==============================================================================

output "lighthouse_authorizations" {
  description = "List of Azure Lighthouse authorizations"
  value = [
    {
      principal_id           = data.azuread_group.msp_administrators.object_id
      principal_display_name = "MSP Administrators"
      role_definition_id     = "b24988ac-6180-42a0-ab88-20f7382dd24c"
      role_name             = "Contributor"
    },
    {
      principal_id           = data.azuread_group.msp_engineers.object_id
      principal_display_name = "MSP Engineers"
      role_definition_id     = "9980e02c-c2be-4d73-94e8-173b1dc7cf3c"
      role_name             = "Virtual Machine Contributor"
    },
    {
      principal_id           = data.azuread_group.msp_administrators.object_id
      principal_display_name = "MSP Administrators - Automanage"
      role_definition_id     = "cdfd5644-ae35-4c17-bb47-ac720c1b0b59"
      role_name             = "Automanage Contributor"
    },
    {
      principal_id           = data.azuread_group.msp_administrators.object_id
      principal_display_name = "MSP Administrators - Log Analytics"
      role_definition_id     = "92aaf0da-9dab-42b6-94a3-d43ce8d16293"
      role_name             = "Log Analytics Contributor"
    },
    {
      principal_id           = data.azuread_group.msp_engineers.object_id
      principal_display_name = "MSP Engineers - Monitoring"
      role_definition_id     = "43d0d8ad-25c7-4714-9337-8ba259a9fe05"
      role_name             = "Monitoring Reader"
    }
  ]
}

output "automanage_configuration_settings" {
  description = "Azure Automanage configuration settings"
  value = {
    antimalware_enabled             = var.enable_antimalware
    azure_security_center_enabled  = var.enable_azure_security_center
    backup_enabled                  = var.enable_backup
    boot_diagnostics_enabled        = var.enable_boot_diagnostics
    change_tracking_enabled         = var.enable_change_tracking
    guest_configuration_enabled     = var.enable_guest_configuration
    log_analytics_enabled           = true
    update_management_enabled       = var.enable_update_management
    vm_insights_enabled             = var.enable_vm_insights
  }
}

# ==============================================================================
# CONNECTIVITY OUTPUTS
# ==============================================================================

output "rdp_connection_command" {
  description = "Command to RDP to the customer virtual machine"
  value       = "mstsc /v:${azurerm_public_ip.customer_vm_pip.ip_address}"
}

output "ssh_connection_command" {
  description = "Command to SSH to the customer virtual machine (if applicable)"
  value       = "ssh ${var.vm_admin_username}@${azurerm_public_ip.customer_vm_pip.ip_address}"
}

# ==============================================================================
# MANAGEMENT URLS
# ==============================================================================

output "azure_lighthouse_portal_url" {
  description = "URL to view Azure Lighthouse delegations in the Azure portal"
  value       = "https://portal.azure.com/#blade/Microsoft_Azure_CustomerHub/ServiceProvidersBladeV2/providers"
}

output "log_analytics_workspace_url" {
  description = "URL to access the Log Analytics workspace"
  value       = "https://portal.azure.com/#@${var.msp_tenant_id}/resource${azurerm_log_analytics_workspace.lighthouse_monitoring.id}/overview"
}

output "customer_vm_portal_url" {
  description = "URL to access the customer VM in the Azure portal"
  value       = "https://portal.azure.com/#@${var.customer_tenant_id}/resource${azurerm_windows_virtual_machine.customer_vm.id}/overview"
}

# ==============================================================================
# SUMMARY OUTPUT
# ==============================================================================

output "deployment_summary" {
  description = "Summary of the deployed cross-tenant governance solution"
  value = {
    solution_name           = "Cross-Tenant Resource Governance with Azure Lighthouse and Azure Automanage"
    managing_tenant_id      = var.msp_tenant_id
    managed_tenant_id       = var.customer_tenant_id
    lighthouse_definition   = azurerm_lighthouse_definition.cross_tenant_governance.name
    automanage_profile      = azurerm_automanage_configuration.lighthouse_profile.name
    managed_vms            = [azurerm_windows_virtual_machine.customer_vm.name]
    monitoring_workspace   = azurerm_log_analytics_workspace.lighthouse_monitoring.name
    alert_email            = var.alert_email_address
    deployment_region      = var.location
    deployment_timestamp   = timestamp()
  }
}