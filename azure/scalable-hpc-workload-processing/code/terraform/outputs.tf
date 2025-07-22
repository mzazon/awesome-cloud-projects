# Outputs for Azure HPC Workload Processing Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.hpc.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.hpc.id
}

output "location" {
  description = "Azure region where resources were deployed"
  value       = azurerm_resource_group.hpc.location
}

# Network Configuration
output "virtual_network_name" {
  description = "Name of the HPC virtual network"
  value       = azurerm_virtual_network.hpc_vnet.name
}

output "virtual_network_id" {
  description = "ID of the HPC virtual network"
  value       = azurerm_virtual_network.hpc_vnet.id
}

output "subnet_name" {
  description = "Name of the Batch subnet"
  value       = azurerm_subnet.batch_subnet.name
}

output "subnet_id" {
  description = "ID of the Batch subnet"
  value       = azurerm_subnet.batch_subnet.id
}

output "network_security_group_name" {
  description = "Name of the network security group"
  value       = azurerm_network_security_group.hpc_nsg.name
}

output "network_security_group_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.hpc_nsg.id
}

# Storage Configuration
output "storage_account_name" {
  description = "Name of the Batch storage account"
  value       = azurerm_storage_account.batch_storage.name
}

output "storage_account_id" {
  description = "ID of the Batch storage account"
  value       = azurerm_storage_account.batch_storage.id
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.batch_storage.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.batch_storage.primary_access_key
  sensitive   = true
}

# Azure Elastic SAN Configuration
output "elastic_san_name" {
  description = "Name of the Azure Elastic SAN"
  value       = azurerm_elastic_san.hpc_esan.name
}

output "elastic_san_id" {
  description = "ID of the Azure Elastic SAN"
  value       = azurerm_elastic_san.hpc_esan.id
}

output "elastic_san_total_iops" {
  description = "Total IOPS capacity of the Elastic SAN"
  value       = azurerm_elastic_san.hpc_esan.total_iops
}

output "elastic_san_total_mbps" {
  description = "Total MBps throughput of the Elastic SAN"
  value       = azurerm_elastic_san.hpc_esan.total_mbps
}

output "elastic_san_total_size_tib" {
  description = "Total size of the Elastic SAN in TiB"
  value       = azurerm_elastic_san.hpc_esan.total_size_in_tib
}

output "elastic_san_volume_group_name" {
  description = "Name of the Elastic SAN volume group"
  value       = azurerm_elastic_san_volume_group.hpc_volume_group.name
}

output "elastic_san_volume_group_id" {
  description = "ID of the Elastic SAN volume group"
  value       = azurerm_elastic_san_volume_group.hpc_volume_group.id
}

# Elastic SAN Volumes
output "data_input_volume_name" {
  description = "Name of the data input volume"
  value       = azurerm_elastic_san_volume.data_input.name
}

output "data_input_volume_id" {
  description = "ID of the data input volume"
  value       = azurerm_elastic_san_volume.data_input.id
}

output "data_input_volume_target_iqn" {
  description = "iSCSI target IQN for the data input volume"
  value       = azurerm_elastic_san_volume.data_input.target_iqn
}

output "data_input_volume_target_portal_hostname" {
  description = "iSCSI target portal hostname for the data input volume"
  value       = azurerm_elastic_san_volume.data_input.target_portal_hostname
}

output "data_input_volume_target_portal_port" {
  description = "iSCSI target portal port for the data input volume"
  value       = azurerm_elastic_san_volume.data_input.target_portal_port
}

output "results_output_volume_name" {
  description = "Name of the results output volume"
  value       = azurerm_elastic_san_volume.results_output.name
}

output "results_output_volume_id" {
  description = "ID of the results output volume"
  value       = azurerm_elastic_san_volume.results_output.id
}

output "results_output_volume_target_iqn" {
  description = "iSCSI target IQN for the results output volume"
  value       = azurerm_elastic_san_volume.results_output.target_iqn
}

output "results_output_volume_target_portal_hostname" {
  description = "iSCSI target portal hostname for the results output volume"
  value       = azurerm_elastic_san_volume.results_output.target_portal_hostname
}

output "results_output_volume_target_portal_port" {
  description = "iSCSI target portal port for the results output volume"
  value       = azurerm_elastic_san_volume.results_output.target_portal_port
}

output "shared_libraries_volume_name" {
  description = "Name of the shared libraries volume"
  value       = azurerm_elastic_san_volume.shared_libraries.name
}

output "shared_libraries_volume_id" {
  description = "ID of the shared libraries volume"
  value       = azurerm_elastic_san_volume.shared_libraries.id
}

output "shared_libraries_volume_target_iqn" {
  description = "iSCSI target IQN for the shared libraries volume"
  value       = azurerm_elastic_san_volume.shared_libraries.target_iqn
}

output "shared_libraries_volume_target_portal_hostname" {
  description = "iSCSI target portal hostname for the shared libraries volume"
  value       = azurerm_elastic_san_volume.shared_libraries.target_portal_hostname
}

output "shared_libraries_volume_target_portal_port" {
  description = "iSCSI target portal port for the shared libraries volume"
  value       = azurerm_elastic_san_volume.shared_libraries.target_portal_port
}

# Azure Batch Configuration
output "batch_account_name" {
  description = "Name of the Azure Batch account"
  value       = azurerm_batch_account.hpc_batch.name
}

output "batch_account_id" {
  description = "ID of the Azure Batch account"
  value       = azurerm_batch_account.hpc_batch.id
}

output "batch_account_endpoint" {
  description = "Endpoint URL of the Azure Batch account"
  value       = azurerm_batch_account.hpc_batch.account_endpoint
}

output "batch_account_primary_access_key" {
  description = "Primary access key for the Batch account"
  value       = azurerm_batch_account.hpc_batch.primary_access_key
  sensitive   = true
}

output "batch_account_secondary_access_key" {
  description = "Secondary access key for the Batch account"
  value       = azurerm_batch_account.hpc_batch.secondary_access_key
  sensitive   = true
}

output "batch_pool_name" {
  description = "Name of the HPC Batch pool"
  value       = azurerm_batch_pool.hpc_pool.name
}

output "batch_pool_id" {
  description = "ID of the HPC Batch pool"
  value       = azurerm_batch_pool.hpc_pool.id
}

output "batch_pool_vm_size" {
  description = "VM size used in the Batch pool"
  value       = azurerm_batch_pool.hpc_pool.vm_size
}

# Monitoring Configuration
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.hpc_monitoring.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.hpc_monitoring.id
}

output "log_analytics_workspace_resource_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.hpc_monitoring.id
}

output "log_analytics_workspace_primary_key" {
  description = "Primary key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.hpc_monitoring.primary_shared_key
  sensitive   = true
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.hpc_insights.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.hpc_insights.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.hpc_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.hpc_insights.connection_string
  sensitive   = true
}

output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = azurerm_monitor_action_group.hpc_alerts.name
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = azurerm_monitor_action_group.hpc_alerts.id
}

# Connection Information
output "iscsi_connection_info" {
  description = "iSCSI connection information for all volumes"
  value = {
    data_input = {
      target_iqn      = azurerm_elastic_san_volume.data_input.target_iqn
      target_hostname = azurerm_elastic_san_volume.data_input.target_portal_hostname
      target_port     = azurerm_elastic_san_volume.data_input.target_portal_port
    }
    results_output = {
      target_iqn      = azurerm_elastic_san_volume.results_output.target_iqn
      target_hostname = azurerm_elastic_san_volume.results_output.target_portal_hostname
      target_port     = azurerm_elastic_san_volume.results_output.target_portal_port
    }
    shared_libraries = {
      target_iqn      = azurerm_elastic_san_volume.shared_libraries.target_iqn
      target_hostname = azurerm_elastic_san_volume.shared_libraries.target_portal_hostname
      target_port     = azurerm_elastic_san_volume.shared_libraries.target_portal_port
    }
  }
}

# Cost Information
output "estimated_monthly_cost_summary" {
  description = "Estimated monthly cost summary for the HPC infrastructure"
  value = {
    description = "Cost estimates vary based on usage patterns"
    elastic_san = "Approximately $300-600/month for 3TiB Premium SAN"
    batch_compute = "Variable based on VM hours and auto-scaling configuration"
    storage_account = "Minimal cost for scripts and logs storage"
    monitoring = "Approximately $50-100/month for Log Analytics and Application Insights"
    note = "Actual costs depend on workload intensity and scaling patterns"
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Commands to get started with the HPC infrastructure"
  value = {
    login_to_batch = "az batch account login --name ${azurerm_batch_account.hpc_batch.name} --resource-group ${azurerm_resource_group.hpc.name}"
    create_job = "az batch job create --id 'hpc-job' --pool-id '${azurerm_batch_pool.hpc_pool.name}'"
    monitor_pool = "az batch pool show --pool-id '${azurerm_batch_pool.hpc_pool.name}' --query '{id:id,state:state,currentNodes:currentDedicatedNodes}'"
    view_logs = "az monitor log-analytics query --workspace '${azurerm_log_analytics_workspace.hpc_monitoring.id}' --analytics-query 'AzureDiagnostics | where ResourceProvider == \"MICROSOFT.BATCH\" | limit 10'"
  }
}