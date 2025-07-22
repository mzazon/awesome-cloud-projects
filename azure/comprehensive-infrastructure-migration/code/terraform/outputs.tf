# Resource Group Outputs
output "source_resource_group_name" {
  description = "Name of the source resource group"
  value       = azurerm_resource_group.source.name
}

output "source_resource_group_id" {
  description = "ID of the source resource group"
  value       = azurerm_resource_group.source.id
}

output "target_resource_group_name" {
  description = "Name of the target resource group"
  value       = azurerm_resource_group.target.name
}

output "target_resource_group_id" {
  description = "ID of the target resource group"
  value       = azurerm_resource_group.target.id
}

# Virtual Machine Outputs
output "vm_name" {
  description = "Name of the test virtual machine"
  value       = azurerm_linux_virtual_machine.test.name
}

output "vm_id" {
  description = "ID of the test virtual machine"
  value       = azurerm_linux_virtual_machine.test.id
}

output "vm_public_ip" {
  description = "Public IP address of the test virtual machine"
  value       = azurerm_public_ip.vm.ip_address
}

output "vm_private_ip" {
  description = "Private IP address of the test virtual machine"
  value       = azurerm_network_interface.vm.private_ip_address
}

output "vm_admin_username" {
  description = "Administrator username for the virtual machine"
  value       = azurerm_linux_virtual_machine.test.admin_username
}

# Network Outputs
output "virtual_network_id" {
  description = "ID of the source virtual network"
  value       = azurerm_virtual_network.source.id
}

output "virtual_network_name" {
  description = "Name of the source virtual network"
  value       = azurerm_virtual_network.source.name
}

output "subnet_id" {
  description = "ID of the default subnet"
  value       = azurerm_subnet.source.id
}

output "network_security_group_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.source.id
}

output "network_interface_id" {
  description = "ID of the VM network interface"
  value       = azurerm_network_interface.vm.id
}

# Storage Outputs
output "os_disk_id" {
  description = "ID of the VM OS disk"
  value       = azurerm_linux_virtual_machine.test.os_disk[0].name
}

output "data_disk_id" {
  description = "ID of the VM data disk"
  value       = azurerm_managed_disk.data.id
}

output "data_disk_name" {
  description = "Name of the VM data disk"
  value       = azurerm_managed_disk.data.name
}

# Update Manager Outputs
output "maintenance_configuration_id" {
  description = "ID of the maintenance configuration for Update Manager"
  value       = azurerm_maintenance_configuration.vm_updates.id
}

output "maintenance_configuration_name" {
  description = "Name of the maintenance configuration"
  value       = azurerm_maintenance_configuration.vm_updates.name
}

output "maintenance_window_start_time" {
  description = "Start time of the maintenance window"
  value       = var.maintenance_window_start_time
}

output "maintenance_window_duration" {
  description = "Duration of the maintenance window in hours"
  value       = var.maintenance_window_duration
}

output "maintenance_window_day" {
  description = "Day of the week for maintenance window"
  value       = var.maintenance_window_day
}

# Monitoring and Logging Outputs
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.name
}

output "log_analytics_workspace_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.primary_shared_key
  sensitive   = true
}

output "log_analytics_customer_id" {
  description = "Customer ID (Workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.migration.workspace_id
}

output "workbook_name" {
  description = "Name of the migration monitoring workbook"
  value       = azurerm_application_insights_workbook.migration_monitoring.display_name
}

output "workbook_id" {
  description = "ID of the migration monitoring workbook"
  value       = azurerm_application_insights_workbook.migration_monitoring.id
}

# Data Collection Rule Outputs (if monitoring is enabled)
output "data_collection_rule_id" {
  description = "ID of the data collection rule for VM monitoring"
  value       = var.enable_monitoring ? azurerm_monitor_data_collection_rule.vm_monitoring[0].id : null
}

output "data_collection_rule_name" {
  description = "Name of the data collection rule for VM monitoring"
  value       = var.enable_monitoring ? azurerm_monitor_data_collection_rule.vm_monitoring[0].name : null
}

# SSH Key Outputs (if generated)
output "ssh_private_key_path" {
  description = "Path to the generated SSH private key file"
  value       = var.vm_admin_password == null && !fileexists(var.ssh_public_key_path) ? local_file.ssh_private_key[0].filename : null
}

output "ssh_public_key_content" {
  description = "Content of the SSH public key"
  value = var.vm_admin_password == null ? (
    fileexists(var.ssh_public_key_path) ? file(var.ssh_public_key_path) : (
      length(local_file.ssh_public_key) > 0 ? local_file.ssh_public_key[0].content : null
    )
  ) : null
  sensitive = false
}

# Azure Resource Mover Commands
output "resource_mover_commands" {
  description = "Azure CLI commands to set up and execute the migration"
  value = {
    install_extension = "az extension add --name resource-mover"
    create_move_collection = "az resource-mover move-collection create --resource-group ${azurerm_resource_group.source.name} --move-collection-name mc-${local.name_prefix}-${local.random_suffix} --source-region '${var.source_region}' --target-region '${var.target_region}' --location '${var.source_region}'"
    add_vm_to_collection = "az resource-mover move-resource create --resource-group ${azurerm_resource_group.source.name} --move-collection-name mc-${local.name_prefix}-${local.random_suffix} --name ${azurerm_linux_virtual_machine.test.name} --source-id ${azurerm_linux_virtual_machine.test.id} --target-resource-group ${azurerm_resource_group.target.name}"
    add_vnet_to_collection = "az resource-mover move-resource create --resource-group ${azurerm_resource_group.source.name} --move-collection-name mc-${local.name_prefix}-${local.random_suffix} --name ${azurerm_virtual_network.source.name} --source-id ${azurerm_virtual_network.source.id} --target-resource-group ${azurerm_resource_group.target.name}"
    add_nsg_to_collection = "az resource-mover move-resource create --resource-group ${azurerm_resource_group.source.name} --move-collection-name mc-${local.name_prefix}-${local.random_suffix} --name ${azurerm_network_security_group.source.name} --source-id ${azurerm_network_security_group.source.id} --target-resource-group ${azurerm_resource_group.target.name}"
    validate_migration = "az resource-mover move-collection validate --resource-group ${azurerm_resource_group.source.name} --move-collection-name mc-${local.name_prefix}-${local.random_suffix}"
    prepare_migration = "az resource-mover move-resource prepare --resource-group ${azurerm_resource_group.source.name} --move-collection-name mc-${local.name_prefix}-${local.random_suffix} --move-resource-name ${azurerm_linux_virtual_machine.test.name}"
    initiate_migration = "az resource-mover move-resource initiate-move --resource-group ${azurerm_resource_group.source.name} --move-collection-name mc-${local.name_prefix}-${local.random_suffix} --move-resource-name ${azurerm_linux_virtual_machine.test.name}"
    commit_migration = "az resource-mover move-resource commit --resource-group ${azurerm_resource_group.source.name} --move-collection-name mc-${local.name_prefix}-${local.random_suffix} --move-resource-name ${azurerm_linux_virtual_machine.test.name}"
  }
}

# Update Manager Commands
output "update_manager_commands" {
  description = "Azure CLI commands to configure Update Manager for migrated resources"
  value = {
    assign_maintenance_config = "az maintenance assignment create --resource-group ${azurerm_resource_group.target.name} --assignment-name assignment-${local.random_suffix} --maintenance-configuration-id ${azurerm_maintenance_configuration.vm_updates.id} --resource-id [MIGRATED_VM_ID]"
    trigger_assessment = "az vm run-command invoke --resource-group ${azurerm_resource_group.target.name} --name [MIGRATED_VM_NAME] --command-id RunShellScript --scripts 'sudo apt update && sudo apt list --upgradable'"
    enable_monitoring = "az vm monitor enable --resource-group ${azurerm_resource_group.target.name} --name [MIGRATED_VM_NAME] --log-analytics-workspace ${azurerm_log_analytics_workspace.migration.name}"
  }
}

# Connection Instructions
output "connection_instructions" {
  description = "Instructions for connecting to the test VM"
  value = {
    ssh_command = var.vm_admin_password == null ? "ssh -i ${var.vm_admin_password == null && !fileexists(var.ssh_public_key_path) ? local_file.ssh_private_key[0].filename : var.ssh_public_key_path} ${azurerm_linux_virtual_machine.test.admin_username}@${azurerm_public_ip.vm.ip_address}" : "Use password authentication with username: ${azurerm_linux_virtual_machine.test.admin_username}"
    web_access = "http://${azurerm_public_ip.vm.ip_address}"
  }
}

# Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring and management portals"
  value = {
    azure_portal_vm = "https://portal.azure.com/#@/resource${azurerm_linux_virtual_machine.test.id}"
    azure_portal_log_analytics = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.migration.id}"
    azure_portal_workbook = "https://portal.azure.com/#@/resource${azurerm_application_insights_workbook.migration_monitoring.id}"
    azure_portal_maintenance_config = "https://portal.azure.com/#@/resource${azurerm_maintenance_configuration.vm_updates.id}"
  }
}

# Cost Information
output "estimated_costs" {
  description = "Estimated monthly costs for the deployed resources (USD)"
  value = {
    vm_b2s = "$30-40 per month"
    premium_ssd_64gb = "$10-15 per month"
    public_ip = "$3-5 per month"
    log_analytics = "$2-10 per month (depends on data ingestion)"
    total_estimate = "$45-70 per month"
    note = "Costs are estimates and may vary based on region and actual usage. Always check current Azure pricing."
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Connect to the VM using SSH to verify it's working correctly",
    "2. Install the Azure Resource Mover CLI extension: az extension add --name resource-mover",
    "3. Create a move collection using the provided command in resource_mover_commands output",
    "4. Add resources to the move collection for migration testing",
    "5. Validate and prepare the migration using Azure Resource Mover",
    "6. Execute the migration workflow when ready",
    "7. Apply Update Manager configuration to migrated resources",
    "8. Monitor the migration process using the Azure Workbook",
    "9. Review migration results and clean up test resources when complete"
  ]
}