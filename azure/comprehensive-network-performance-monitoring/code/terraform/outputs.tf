# outputs.tf
# Output values for Azure Network Performance Monitoring solution

# ====================================================================
# RESOURCE GROUP OUTPUTS
# ====================================================================

output "resource_group_name" {
  description = "Name of the resource group containing all monitoring resources"
  value       = azurerm_resource_group.monitoring.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.monitoring.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.monitoring.id
}

# ====================================================================
# NETWORKING OUTPUTS
# ====================================================================

output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.monitoring.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.monitoring.id
}

output "subnet_name" {
  description = "Name of the monitoring subnet"
  value       = azurerm_subnet.monitoring.name
}

output "subnet_id" {
  description = "ID of the monitoring subnet"
  value       = azurerm_subnet.monitoring.id
}

output "network_security_group_name" {
  description = "Name of the network security group"
  value       = azurerm_network_security_group.monitoring.name
}

output "network_security_group_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.monitoring.id
}

# ====================================================================
# MONITORING INFRASTRUCTURE OUTPUTS
# ====================================================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.monitoring.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.monitoring.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.monitoring.workspace_id
  sensitive   = true
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.monitoring.primary_shared_key
  sensitive   = true
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.monitoring.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.monitoring.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of the Application Insights instance"
  value       = azurerm_application_insights.monitoring.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string of the Application Insights instance"
  value       = azurerm_application_insights.monitoring.connection_string
  sensitive   = true
}

# ====================================================================
# STORAGE OUTPUTS
# ====================================================================

output "storage_account_name" {
  description = "Name of the storage account for flow logs"
  value       = azurerm_storage_account.monitoring.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.monitoring.id
}

output "storage_account_primary_access_key" {
  description = "Primary access key of the storage account"
  value       = azurerm_storage_account.monitoring.primary_access_key
  sensitive   = true
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string of the storage account"
  value       = azurerm_storage_account.monitoring.primary_connection_string
  sensitive   = true
}

# ====================================================================
# VIRTUAL MACHINE OUTPUTS
# ====================================================================

output "source_vm_name" {
  description = "Name of the source virtual machine"
  value       = azurerm_linux_virtual_machine.source_vm.name
}

output "source_vm_id" {
  description = "ID of the source virtual machine"
  value       = azurerm_linux_virtual_machine.source_vm.id
}

output "source_vm_public_ip" {
  description = "Public IP address of the source virtual machine"
  value       = azurerm_public_ip.source_vm.ip_address
}

output "source_vm_private_ip" {
  description = "Private IP address of the source virtual machine"
  value       = azurerm_network_interface.source_vm.private_ip_address
}

output "dest_vm_name" {
  description = "Name of the destination virtual machine"
  value       = azurerm_linux_virtual_machine.dest_vm.name
}

output "dest_vm_id" {
  description = "ID of the destination virtual machine"
  value       = azurerm_linux_virtual_machine.dest_vm.id
}

output "dest_vm_public_ip" {
  description = "Public IP address of the destination virtual machine"
  value       = azurerm_public_ip.dest_vm.ip_address
}

output "dest_vm_private_ip" {
  description = "Private IP address of the destination virtual machine"
  value       = azurerm_network_interface.dest_vm.private_ip_address
}

# ====================================================================
# SSH KEY OUTPUTS
# ====================================================================

output "ssh_private_key" {
  description = "Generated SSH private key (if no public key was provided)"
  value       = var.vm_public_key == "" ? tls_private_key.monitoring[0].private_key_pem : null
  sensitive   = true
}

output "ssh_public_key" {
  description = "SSH public key used for VM authentication"
  value       = var.vm_public_key != "" ? var.vm_public_key : tls_private_key.monitoring[0].public_key_openssh
  sensitive   = true
}

# ====================================================================
# NETWORK WATCHER OUTPUTS
# ====================================================================

output "network_watcher_name" {
  description = "Name of the Network Watcher instance"
  value       = data.azurerm_network_watcher.main.name
}

output "network_watcher_resource_group" {
  description = "Resource group of the Network Watcher instance"
  value       = data.azurerm_network_watcher.main.resource_group_name
}

output "connection_monitor_name" {
  description = "Name of the connection monitor"
  value       = azurerm_network_connection_monitor.monitoring.name
}

output "connection_monitor_id" {
  description = "ID of the connection monitor"
  value       = azurerm_network_connection_monitor.monitoring.id
}

output "flow_log_name" {
  description = "Name of the NSG flow log"
  value       = var.enable_flow_logs ? azurerm_network_watcher_flow_log.monitoring[0].name : null
}

output "flow_log_id" {
  description = "ID of the NSG flow log"
  value       = var.enable_flow_logs ? azurerm_network_watcher_flow_log.monitoring[0].id : null
}

# ====================================================================
# ALERTING OUTPUTS
# ====================================================================

output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = var.enable_alerts ? azurerm_monitor_action_group.monitoring[0].name : null
}

output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = var.enable_alerts ? azurerm_monitor_action_group.monitoring[0].id : null
}

output "high_latency_alert_name" {
  description = "Name of the high latency alert rule"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.high_latency[0].name : null
}

output "connectivity_failure_alert_name" {
  description = "Name of the connectivity failure alert rule"
  value       = var.enable_alerts ? azurerm_monitor_metric_alert.connectivity_failure[0].name : null
}

# ====================================================================
# BASTION OUTPUTS
# ====================================================================

output "bastion_host_name" {
  description = "Name of the Azure Bastion host"
  value       = var.create_bastion ? azurerm_bastion_host.monitoring[0].name : null
}

output "bastion_host_id" {
  description = "ID of the Azure Bastion host"
  value       = var.create_bastion ? azurerm_bastion_host.monitoring[0].id : null
}

output "bastion_dns_name" {
  description = "DNS name of the Azure Bastion host"
  value       = var.create_bastion ? azurerm_bastion_host.monitoring[0].dns_name : null
}

# ====================================================================
# MONITORING DASHBOARD QUERIES
# ====================================================================

output "network_monitoring_query" {
  description = "KQL query to analyze network monitoring data"
  value = <<-EOT
    NetworkMonitoring
    | where TimeGenerated > ago(1h)
    | summarize 
        AvgLatency = avg(LatencyMs),
        MaxLatency = max(LatencyMs),
        MinLatency = min(LatencyMs),
        AvgPacketLoss = avg(PacketLossPercent),
        TotalTests = count()
    by bin(TimeGenerated, 5m), TestName, SourceName, DestinationName
    | render timechart
  EOT
}

output "connection_success_rate_query" {
  description = "KQL query to analyze connection success rates"
  value = <<-EOT
    NetworkMonitoring
    | where TimeGenerated > ago(24h)
    | summarize
        SuccessfulTests = countif(TestResult == "Success"),
        FailedTests = countif(TestResult == "Failed"),
        TotalTests = count()
    by TestName, SourceName, DestinationName
    | extend SuccessRate = round(SuccessfulTests * 100.0 / TotalTests, 2)
    | project TestName, SourceName, DestinationName, SuccessRate, TotalTests
  EOT
}

output "network_performance_correlation_query" {
  description = "KQL query to correlate network performance with application metrics"
  value = <<-EOT
    let NetworkData = NetworkMonitoring
    | where TimeGenerated > ago(1h)
    | summarize AvgLatency = avg(LatencyMs), AvgPacketLoss = avg(PacketLossPercent) by bin(TimeGenerated, 5m);
    
    let AppData = requests
    | where timestamp > ago(1h)
    | summarize AvgResponseTime = avg(duration) by bin(timestamp, 5m);
    
    NetworkData
    | join kind=inner (AppData) on $left.TimeGenerated == $right.timestamp
    | project TimeGenerated, AvgLatency, AvgPacketLoss, AvgResponseTime
    | render timechart
  EOT
}

# ====================================================================
# DEPLOYMENT INFORMATION
# ====================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group    = azurerm_resource_group.monitoring.name
    location          = azurerm_resource_group.monitoring.location
    project_name      = var.project_name
    environment       = var.environment
    random_suffix     = random_string.suffix.result
    
    monitoring = {
      log_analytics_workspace = azurerm_log_analytics_workspace.monitoring.name
      application_insights     = azurerm_application_insights.monitoring.name
      storage_account         = azurerm_storage_account.monitoring.name
      connection_monitor      = azurerm_network_connection_monitor.monitoring.name
      flow_logs_enabled       = var.enable_flow_logs
      alerts_enabled          = var.enable_alerts
    }
    
    networking = {
      virtual_network         = azurerm_virtual_network.monitoring.name
      subnet                 = azurerm_subnet.monitoring.name
      network_security_group = azurerm_network_security_group.monitoring.name
      bastion_enabled        = var.create_bastion
    }
    
    virtual_machines = {
      source_vm = {
        name       = azurerm_linux_virtual_machine.source_vm.name
        public_ip  = azurerm_public_ip.source_vm.ip_address
        private_ip = azurerm_network_interface.source_vm.private_ip_address
      }
      dest_vm = {
        name       = azurerm_linux_virtual_machine.dest_vm.name
        public_ip  = azurerm_public_ip.dest_vm.ip_address
        private_ip = azurerm_network_interface.dest_vm.private_ip_address
      }
    }
  }
}

# ====================================================================
# USAGE INSTRUCTIONS
# ====================================================================

output "usage_instructions" {
  description = "Instructions for using the deployed monitoring solution"
  value = <<-EOT
    # Azure Network Performance Monitoring Solution Deployed Successfully!
    
    ## Access Information:
    - Resource Group: ${azurerm_resource_group.monitoring.name}
    - Location: ${azurerm_resource_group.monitoring.location}
    - Log Analytics Workspace: ${azurerm_log_analytics_workspace.monitoring.name}
    - Application Insights: ${azurerm_application_insights.monitoring.name}
    
    ## Virtual Machines:
    - Source VM: ${azurerm_linux_virtual_machine.source_vm.name} (${azurerm_public_ip.source_vm.ip_address})
    - Destination VM: ${azurerm_linux_virtual_machine.dest_vm.name} (${azurerm_public_ip.dest_vm.ip_address})
    - Username: ${var.vm_admin_username}
    
    ## Connection Monitoring:
    - Connection Monitor: ${azurerm_network_connection_monitor.monitoring.name}
    - Test Frequency: ${var.connection_monitor_test_frequency} seconds
    - External Endpoint: ${var.external_endpoint_address}
    
    ## Next Steps:
    1. Wait 5-10 minutes for monitoring data to populate
    2. Access Log Analytics workspace to view network performance metrics
    3. Use Application Insights to correlate network and application performance
    4. Configure additional alert rules as needed
    
    ## Monitoring Queries:
    Use the provided KQL queries in the outputs to analyze network performance data.
    
    ## Cleanup:
    Run 'terraform destroy' to remove all resources and avoid ongoing charges.
  EOT
}