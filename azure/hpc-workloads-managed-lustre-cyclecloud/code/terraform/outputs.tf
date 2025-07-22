# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.hpc.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.hpc.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.hpc.id
}

# Network Infrastructure Outputs
output "virtual_network_name" {
  description = "Name of the HPC virtual network"
  value       = azurerm_virtual_network.hpc_vnet.name
}

output "virtual_network_id" {
  description = "ID of the HPC virtual network"
  value       = azurerm_virtual_network.hpc_vnet.id
}

output "compute_subnet_id" {
  description = "ID of the compute subnet"
  value       = azurerm_subnet.compute_subnet.id
}

output "management_subnet_id" {
  description = "ID of the management subnet"
  value       = azurerm_subnet.management_subnet.id
}

output "storage_subnet_id" {
  description = "ID of the storage subnet"
  value       = azurerm_subnet.storage_subnet.id
}

# Azure Managed Lustre Outputs
output "lustre_file_system_name" {
  description = "Name of the Azure Managed Lustre file system"
  value       = azurerm_managed_lustre_file_system.hpc_lustre.name
}

output "lustre_file_system_id" {
  description = "ID of the Azure Managed Lustre file system"
  value       = azurerm_managed_lustre_file_system.hpc_lustre.id
}

output "lustre_mount_endpoints" {
  description = "Mount endpoints for the Lustre file system"
  value       = azurerm_managed_lustre_file_system.hpc_lustre.client_endpoints
}

output "lustre_mount_command" {
  description = "Command to mount the Lustre file system"
  value       = "sudo mount -t lustre ${azurerm_managed_lustre_file_system.hpc_lustre.client_endpoints[0]}@tcp:/lustrefs /mnt/lustre"
}

output "lustre_storage_capacity_gb" {
  description = "Storage capacity of the Lustre file system in GB"
  value       = azurerm_managed_lustre_file_system.hpc_lustre.storage_capacity_in_tb * 1024
}

output "lustre_throughput_mb_per_sec" {
  description = "Throughput of the Lustre file system in MB/s"
  value       = var.lustre_throughput_per_unit_mb
}

# CycleCloud Server Outputs
output "cyclecloud_server_name" {
  description = "Name of the CycleCloud management server"
  value       = azurerm_linux_virtual_machine.cyclecloud_server.name
}

output "cyclecloud_server_id" {
  description = "ID of the CycleCloud management server"
  value       = azurerm_linux_virtual_machine.cyclecloud_server.id
}

output "cyclecloud_public_ip" {
  description = "Public IP address of the CycleCloud server"
  value       = azurerm_public_ip.cyclecloud_public_ip.ip_address
}

output "cyclecloud_private_ip" {
  description = "Private IP address of the CycleCloud server"
  value       = azurerm_network_interface.cyclecloud_nic.private_ip_address
}

output "cyclecloud_web_url" {
  description = "URL to access the CycleCloud web interface"
  value       = "https://${azurerm_public_ip.cyclecloud_public_ip.ip_address}"
}

output "cyclecloud_ssh_connection" {
  description = "SSH connection command for CycleCloud server"
  value       = "ssh ${var.cyclecloud_admin_username}@${azurerm_public_ip.cyclecloud_public_ip.ip_address}"
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.hpc_storage.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.hpc_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.hpc_storage.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.hpc_storage.primary_connection_string
  sensitive   = true
}

# Security Outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.hpc_kv.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.hpc_kv.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.hpc_kv.vault_uri
}

output "ssh_private_key" {
  description = "Private SSH key for cluster access"
  value       = var.enable_ssh_key_authentication ? tls_private_key.hpc_ssh_key[0].private_key_pem : null
  sensitive   = true
}

output "ssh_public_key" {
  description = "Public SSH key for cluster access"
  value       = var.enable_ssh_key_authentication ? tls_private_key.hpc_ssh_key[0].public_key_openssh : null
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.hpc_monitoring[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.hpc_monitoring[0].id : null
}

output "log_analytics_workspace_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.hpc_monitoring[0].primary_shared_key : null
  sensitive   = true
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.hpc_app_insights[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.hpc_app_insights[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.hpc_app_insights[0].connection_string : null
  sensitive   = true
}

# HPC Configuration Outputs
output "hpc_cluster_name" {
  description = "Name of the HPC cluster"
  value       = var.hpc_cluster_name
}

output "hpc_compute_vm_size" {
  description = "VM size for HPC compute nodes"
  value       = var.hpc_compute_vm_size
}

output "hpc_max_core_count" {
  description = "Maximum core count for HPC cluster"
  value       = var.hpc_max_core_count
}

# Deployment Information
output "deployment_random_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

# Summary Information
output "deployment_summary" {
  description = "Summary of the deployed HPC environment"
  value = {
    resource_group           = azurerm_resource_group.hpc.name
    location                = azurerm_resource_group.hpc.location
    cyclecloud_public_ip     = azurerm_public_ip.cyclecloud_public_ip.ip_address
    cyclecloud_web_url       = "https://${azurerm_public_ip.cyclecloud_public_ip.ip_address}"
    lustre_file_system       = azurerm_managed_lustre_file_system.hpc_lustre.name
    lustre_capacity_tib      = azurerm_managed_lustre_file_system.hpc_lustre.storage_capacity_in_tb
    storage_account          = azurerm_storage_account.hpc_storage.name
    monitoring_enabled       = var.enable_monitoring
    log_analytics_workspace  = var.enable_monitoring ? azurerm_log_analytics_workspace.hpc_monitoring[0].name : "disabled"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps to configure the HPC environment"
  value = [
    "1. SSH to CycleCloud server: ssh ${var.cyclecloud_admin_username}@${azurerm_public_ip.cyclecloud_public_ip.ip_address}",
    "2. Access CycleCloud web interface: https://${azurerm_public_ip.cyclecloud_public_ip.ip_address}",
    "3. Initialize CycleCloud: cyclecloud initialize --batch",
    "4. Create HPC cluster: cyclecloud create_cluster slurm ${var.hpc_cluster_name}",
    "5. Configure Lustre mount: sudo mount -t lustre ${azurerm_managed_lustre_file_system.hpc_lustre.client_endpoints[0]}@tcp:/lustrefs /mnt/lustre",
    "6. Start cluster: cyclecloud start_cluster ${var.hpc_cluster_name}",
    "7. Submit test job through Slurm scheduler",
    "8. Monitor performance through Azure Monitor"
  ]
}