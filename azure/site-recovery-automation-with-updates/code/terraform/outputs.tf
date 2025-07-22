# Output values for Azure Disaster Recovery Solution
# These outputs provide essential information for post-deployment configuration
# and integration with other systems

# ==============================================================================
# RESOURCE GROUP OUTPUTS
# ==============================================================================

output "primary_resource_group_name" {
  description = "Name of the primary resource group"
  value       = azurerm_resource_group.primary.name
}

output "secondary_resource_group_name" {
  description = "Name of the secondary resource group"
  value       = azurerm_resource_group.secondary.name
}

output "primary_resource_group_id" {
  description = "ID of the primary resource group"
  value       = azurerm_resource_group.primary.id
}

output "secondary_resource_group_id" {
  description = "ID of the secondary resource group"
  value       = azurerm_resource_group.secondary.id
}

output "primary_location" {
  description = "Azure region for primary resources"
  value       = azurerm_resource_group.primary.location
}

output "secondary_location" {
  description = "Azure region for secondary resources"
  value       = azurerm_resource_group.secondary.location
}

# ==============================================================================
# NETWORKING OUTPUTS
# ==============================================================================

output "primary_vnet_name" {
  description = "Name of the primary virtual network"
  value       = azurerm_virtual_network.primary.name
}

output "secondary_vnet_name" {
  description = "Name of the secondary virtual network"
  value       = azurerm_virtual_network.secondary.name
}

output "primary_vnet_id" {
  description = "ID of the primary virtual network"
  value       = azurerm_virtual_network.primary.id
}

output "secondary_vnet_id" {
  description = "ID of the secondary virtual network"
  value       = azurerm_virtual_network.secondary.id
}

output "primary_subnet_id" {
  description = "ID of the primary subnet"
  value       = azurerm_subnet.primary.id
}

output "secondary_subnet_id" {
  description = "ID of the secondary subnet"
  value       = azurerm_subnet.secondary.id
}

output "primary_nsg_id" {
  description = "ID of the primary network security group"
  value       = azurerm_network_security_group.primary.id
}

output "secondary_nsg_id" {
  description = "ID of the secondary network security group"
  value       = azurerm_network_security_group.secondary.id
}

# ==============================================================================
# VIRTUAL MACHINE OUTPUTS
# ==============================================================================

output "primary_vm_name" {
  description = "Name of the primary virtual machine"
  value       = azurerm_windows_virtual_machine.primary.name
}

output "primary_vm_id" {
  description = "ID of the primary virtual machine"
  value       = azurerm_windows_virtual_machine.primary.id
}

output "primary_vm_private_ip" {
  description = "Private IP address of the primary virtual machine"
  value       = azurerm_network_interface.primary_vm.private_ip_address
}

output "primary_vm_public_ip" {
  description = "Public IP address of the primary virtual machine"
  value       = azurerm_public_ip.primary_vm.ip_address
}

output "primary_vm_fqdn" {
  description = "Fully qualified domain name of the primary virtual machine"
  value       = azurerm_public_ip.primary_vm.fqdn
}

output "primary_vm_admin_username" {
  description = "Admin username for the primary virtual machine"
  value       = azurerm_windows_virtual_machine.primary.admin_username
}

output "primary_vm_size" {
  description = "Size of the primary virtual machine"
  value       = azurerm_windows_virtual_machine.primary.size
}

# ==============================================================================
# RECOVERY SERVICES OUTPUTS
# ==============================================================================

output "recovery_services_vault_name" {
  description = "Name of the Recovery Services Vault"
  value       = azurerm_recovery_services_vault.main.name
}

output "recovery_services_vault_id" {
  description = "ID of the Recovery Services Vault"
  value       = azurerm_recovery_services_vault.main.id
}

output "backup_policy_id" {
  description = "ID of the backup policy"
  value       = azurerm_backup_policy_vm.main.id
}

output "backup_policy_name" {
  description = "Name of the backup policy"
  value       = azurerm_backup_policy_vm.main.name
}

output "protected_vm_id" {
  description = "ID of the protected VM backup item"
  value       = azurerm_backup_protected_vm.primary.id
}

# ==============================================================================
# SITE RECOVERY OUTPUTS
# ==============================================================================

output "site_recovery_fabric_primary_name" {
  description = "Name of the primary Site Recovery fabric"
  value       = azurerm_site_recovery_fabric.primary.name
}

output "site_recovery_fabric_secondary_name" {
  description = "Name of the secondary Site Recovery fabric"
  value       = azurerm_site_recovery_fabric.secondary.name
}

output "site_recovery_container_primary_name" {
  description = "Name of the primary Site Recovery protection container"
  value       = azurerm_site_recovery_protection_container.primary.name
}

output "site_recovery_container_secondary_name" {
  description = "Name of the secondary Site Recovery protection container"
  value       = azurerm_site_recovery_protection_container.secondary.name
}

output "cache_storage_account_name" {
  description = "Name of the cache storage account"
  value       = azurerm_storage_account.cache.name
}

output "cache_storage_account_id" {
  description = "ID of the cache storage account"
  value       = azurerm_storage_account.cache.id
}

# ==============================================================================
# MONITORING AND AUTOMATION OUTPUTS
# ==============================================================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_resource_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "automation_account_name" {
  description = "Name of the Azure Automation account"
  value       = azurerm_automation_account.main.name
}

output "automation_account_id" {
  description = "ID of the Azure Automation account"
  value       = azurerm_automation_account.main.id
}

output "automation_runbook_name" {
  description = "Name of the disaster recovery orchestration runbook"
  value       = azurerm_automation_runbook.dr_orchestration.name
}

output "action_group_name" {
  description = "Name of the action group for disaster recovery alerts"
  value       = azurerm_monitor_action_group.dr_alerts.name
}

output "action_group_id" {
  description = "ID of the action group for disaster recovery alerts"
  value       = azurerm_monitor_action_group.dr_alerts.id
}

# ==============================================================================
# SOLUTION MONITORING OUTPUTS
# ==============================================================================

output "update_management_solution_id" {
  description = "ID of the Update Management solution"
  value       = var.enable_update_management ? azurerm_log_analytics_solution.update_management[0].id : null
}

output "change_tracking_solution_id" {
  description = "ID of the Change Tracking solution"
  value       = var.enable_change_tracking ? azurerm_log_analytics_solution.change_tracking[0].id : null
}

output "vm_cpu_alert_id" {
  description = "ID of the VM CPU usage alert"
  value       = azurerm_monitor_metric_alert.vm_cpu.id
}

output "backup_failure_alert_id" {
  description = "ID of the backup failure alert"
  value       = azurerm_monitor_metric_alert.backup_failure.id
}

# ==============================================================================
# NETWORK WATCHER OUTPUTS
# ==============================================================================

output "network_watcher_primary_name" {
  description = "Name of the primary Network Watcher"
  value       = var.enable_network_watcher ? azurerm_network_watcher.primary[0].name : null
}

output "network_watcher_secondary_name" {
  description = "Name of the secondary Network Watcher"
  value       = var.enable_network_watcher ? azurerm_network_watcher.secondary[0].name : null
}

output "network_watcher_primary_id" {
  description = "ID of the primary Network Watcher"
  value       = var.enable_network_watcher ? azurerm_network_watcher.primary[0].id : null
}

output "network_watcher_secondary_id" {
  description = "ID of the secondary Network Watcher"
  value       = var.enable_network_watcher ? azurerm_network_watcher.secondary[0].id : null
}

# ==============================================================================
# COST MANAGEMENT OUTPUTS
# ==============================================================================

output "budget_name" {
  description = "Name of the cost management budget"
  value       = var.enable_cost_alerts ? azurerm_consumption_budget_resource_group.main[0].name : null
}

output "budget_amount" {
  description = "Amount of the cost management budget"
  value       = var.enable_cost_alerts ? var.monthly_budget_amount : null
}

# ==============================================================================
# CONNECTIVITY INFORMATION
# ==============================================================================

output "rdp_connection_command" {
  description = "Command to connect to the primary VM via RDP"
  value       = "mstsc /v:${azurerm_public_ip.primary_vm.ip_address}:3389"
}

output "powershell_connection_command" {
  description = "PowerShell command to connect to the primary VM"
  value       = "Enter-PSSession -ComputerName ${azurerm_public_ip.primary_vm.ip_address} -Credential (Get-Credential)"
}

# ==============================================================================
# DEPLOYMENT SUMMARY
# ==============================================================================

output "deployment_summary" {
  description = "Summary of the deployed disaster recovery solution"
  value = {
    primary_region         = azurerm_resource_group.primary.location
    secondary_region       = azurerm_resource_group.secondary.location
    vm_count              = 1
    backup_enabled        = true
    site_recovery_enabled = true
    update_management     = var.enable_update_management
    change_tracking       = var.enable_change_tracking
    network_watcher       = var.enable_network_watcher
    cost_alerts          = var.enable_cost_alerts
    vault_storage_type    = var.vault_storage_model_type
    backup_retention_days = var.backup_retention_daily
  }
}

# ==============================================================================
# NEXT STEPS
# ==============================================================================

output "next_steps" {
  description = "Next steps for completing the disaster recovery setup"
  value = [
    "1. Configure Site Recovery replication for the primary VM",
    "2. Test backup and restore procedures",
    "3. Schedule regular disaster recovery tests",
    "4. Configure update management schedules",
    "5. Review and adjust monitoring thresholds",
    "6. Set up notification channels for alerts",
    "7. Document recovery procedures and contact information"
  ]
}

# ==============================================================================
# IMPORTANT URLS
# ==============================================================================

output "important_urls" {
  description = "Important Azure portal URLs for managing the disaster recovery solution"
  value = {
    recovery_services_vault = "https://portal.azure.com/#@/resource${azurerm_recovery_services_vault.main.id}/overview"
    log_analytics_workspace = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
    automation_account      = "https://portal.azure.com/#@/resource${azurerm_automation_account.main.id}/overview"
    primary_vm             = "https://portal.azure.com/#@/resource${azurerm_windows_virtual_machine.primary.id}/overview"
    cost_management        = "https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview"
    azure_monitor          = "https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/overview"
  }
}

# ==============================================================================
# SECURITY CONSIDERATIONS
# ==============================================================================

output "security_recommendations" {
  description = "Security recommendations for the disaster recovery solution"
  value = [
    "1. Regularly review and update NSG rules",
    "2. Enable Azure Security Center for vulnerability assessments",
    "3. Implement Azure Policy for compliance enforcement",
    "4. Use Azure Key Vault for secrets management",
    "5. Enable Azure AD authentication where possible",
    "6. Regularly review access permissions and roles",
    "7. Monitor for unusual activity in logs and alerts"
  ]
}

# ==============================================================================
# COST OPTIMIZATION TIPS
# ==============================================================================

output "cost_optimization_tips" {
  description = "Tips for optimizing costs in the disaster recovery solution"
  value = [
    "1. Use Azure Reserved VM Instances for predictable workloads",
    "2. Right-size VMs based on actual usage patterns",
    "3. Configure auto-shutdown for development/test environments",
    "4. Use Azure Hybrid Benefit for Windows Server licenses",
    "5. Monitor storage costs and optimize backup retention policies",
    "6. Consider using Azure Spot VMs for non-critical workloads",
    "7. Regularly review and remove unused resources"
  ]
}