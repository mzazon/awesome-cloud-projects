# Outputs for Azure Elastic SAN and VMSS Database Infrastructure
# This file defines all output values that will be displayed after deployment

# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Network Outputs
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "subnet_name" {
  description = "Name of the database subnet"
  value       = azurerm_subnet.database.name
}

output "subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.database.id
}

# Elastic SAN Outputs
output "elastic_san_name" {
  description = "Name of the Elastic SAN"
  value       = azurerm_elastic_san.main.name
}

output "elastic_san_id" {
  description = "ID of the Elastic SAN"
  value       = azurerm_elastic_san.main.id
}

output "elastic_san_total_size_tib" {
  description = "Total size of Elastic SAN in TiB"
  value       = azurerm_elastic_san.main.total_size_tib
}

output "elastic_san_volume_group_name" {
  description = "Name of the Elastic SAN volume group"
  value       = azurerm_elastic_san_volume_group.database.name
}

output "elastic_san_volume_group_id" {
  description = "ID of the Elastic SAN volume group"
  value       = azurerm_elastic_san_volume_group.database.id
}

output "elastic_san_data_volume_name" {
  description = "Name of the data volume"
  value       = azurerm_elastic_san_volume.data.name
}

output "elastic_san_data_volume_id" {
  description = "ID of the data volume"
  value       = azurerm_elastic_san_volume.data.id
}

output "elastic_san_log_volume_name" {
  description = "Name of the log volume"
  value       = azurerm_elastic_san_volume.logs.name
}

output "elastic_san_log_volume_id" {
  description = "ID of the log volume"
  value       = azurerm_elastic_san_volume.logs.id
}

# Virtual Machine Scale Set Outputs
output "vmss_name" {
  description = "Name of the Virtual Machine Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.main.name
}

output "vmss_id" {
  description = "ID of the Virtual Machine Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.main.id
}

output "vmss_instances" {
  description = "Number of instances in the VMSS"
  value       = azurerm_linux_virtual_machine_scale_set.main.instances
}

output "vmss_sku" {
  description = "SKU of the VMSS instances"
  value       = azurerm_linux_virtual_machine_scale_set.main.sku
}

# Load Balancer Outputs
output "load_balancer_name" {
  description = "Name of the load balancer"
  value       = azurerm_lb.main.name
}

output "load_balancer_id" {
  description = "ID of the load balancer"
  value       = azurerm_lb.main.id
}

output "load_balancer_public_ip" {
  description = "Public IP address of the load balancer"
  value       = azurerm_public_ip.lb.ip_address
}

output "load_balancer_fqdn" {
  description = "FQDN of the load balancer"
  value       = azurerm_public_ip.lb.fqdn
}

# PostgreSQL Outputs
output "postgresql_server_name" {
  description = "Name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "postgresql_server_id" {
  description = "ID of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.id
}

output "postgresql_server_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgresql_administrator_login" {
  description = "Administrator login for PostgreSQL"
  value       = azurerm_postgresql_flexible_server.main.administrator_login
}

output "postgresql_version" {
  description = "Version of PostgreSQL"
  value       = azurerm_postgresql_flexible_server.main.version
}

output "postgresql_storage_mb" {
  description = "Storage size of PostgreSQL in MB"
  value       = azurerm_postgresql_flexible_server.main.storage_mb
}

output "postgresql_high_availability_enabled" {
  description = "High availability status of PostgreSQL"
  value       = azurerm_postgresql_flexible_server.main.high_availability[0].mode != ""
}

# Auto-scaling Outputs
output "autoscale_setting_name" {
  description = "Name of the autoscale setting"
  value       = azurerm_monitor_autoscale_setting.vmss.name
}

output "autoscale_setting_id" {
  description = "ID of the autoscale setting"
  value       = azurerm_monitor_autoscale_setting.vmss.id
}

output "autoscale_minimum_instances" {
  description = "Minimum number of instances for autoscaling"
  value       = var.autoscale_minimum_instances
}

output "autoscale_maximum_instances" {
  description = "Maximum number of instances for autoscaling"
  value       = var.autoscale_maximum_instances
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = azurerm_monitor_action_group.main.id
}

output "cpu_alert_name" {
  description = "Name of the CPU alert rule"
  value       = azurerm_monitor_metric_alert.cpu_usage.name
}

output "cpu_alert_id" {
  description = "ID of the CPU alert rule"
  value       = azurerm_monitor_metric_alert.cpu_usage.id
}

# SSH Key Outputs
output "ssh_private_key_pem" {
  description = "Private SSH key for VM access (sensitive)"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}

output "ssh_public_key_openssh" {
  description = "Public SSH key for VM access"
  value       = tls_private_key.ssh.public_key_openssh
}

# Connection Information
output "database_connection_info" {
  description = "Database connection information"
  value = {
    postgresql_connection_string = "postgresql://${azurerm_postgresql_flexible_server.main.administrator_login}:${var.postgresql_administrator_password}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/postgres"
    load_balancer_endpoint      = "${azurerm_public_ip.lb.ip_address}:5432"
    ssh_connection_command      = "ssh -i private_key.pem ${var.admin_username}@${azurerm_public_ip.lb.ip_address}"
  }
  sensitive = true
}

# Resource Summary
output "resource_summary" {
  description = "Summary of deployed resources"
  value = {
    elastic_san_total_capacity_tib = azurerm_elastic_san.main.total_size_tib
    elastic_san_volumes_count     = 2
    vmss_current_instances        = azurerm_linux_virtual_machine_scale_set.main.instances
    postgresql_storage_gb         = azurerm_postgresql_flexible_server.main.storage_mb / 1024
    monitoring_enabled            = true
    high_availability_enabled     = azurerm_postgresql_flexible_server.main.high_availability[0].mode != ""
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    terraform_version = "~> 1.0"
    azurerm_provider_version = "~> 3.0"
    deployment_time = timestamp()
    resource_group = azurerm_resource_group.main.name
    location = azurerm_resource_group.main.location
  }
}