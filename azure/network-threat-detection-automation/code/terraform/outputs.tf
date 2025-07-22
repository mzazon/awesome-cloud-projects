# Outputs for Azure Network Threat Detection Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group containing all resources"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for NSG flow logs"
  value       = azurerm_storage_account.flow_logs.name
}

output "storage_account_id" {
  description = "ID of the storage account for NSG flow logs"
  value       = azurerm_storage_account.flow_logs.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.flow_logs.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.flow_logs.primary_connection_string
  sensitive   = true
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_portal_url" {
  description = "Portal URL for the Log Analytics workspace"
  value       = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/logs"
}

# Network Security Group Information (if demo NSG is created)
output "demo_nsg_name" {
  description = "Name of the demo Network Security Group"
  value       = var.create_demo_nsg ? azurerm_network_security_group.demo[0].name : null
}

output "demo_nsg_id" {
  description = "ID of the demo Network Security Group"
  value       = var.create_demo_nsg ? azurerm_network_security_group.demo[0].id : null
}

# NSG Flow Logs Information
output "nsg_flow_logs_id" {
  description = "ID of the NSG flow logs configuration"
  value       = var.create_demo_nsg ? azurerm_network_watcher_flow_log.demo[0].id : null
}

output "nsg_flow_logs_status" {
  description = "Status of the NSG flow logs"
  value       = var.create_demo_nsg ? azurerm_network_watcher_flow_log.demo[0].enabled : null
}

# Alert Rules Information
output "port_scanning_alert_id" {
  description = "ID of the port scanning alert rule"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.port_scanning.id
}

output "data_exfiltration_alert_id" {
  description = "ID of the data exfiltration alert rule"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.data_exfiltration.id
}

output "failed_connections_alert_id" {
  description = "ID of the failed connections alert rule"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.failed_connections.id
}

# Logic Apps Information
output "logic_app_name" {
  description = "Name of the Logic App for automated response"
  value       = var.enable_logic_apps ? azurerm_logic_app_workflow.threat_response[0].name : null
}

output "logic_app_id" {
  description = "ID of the Logic App for automated response"
  value       = var.enable_logic_apps ? azurerm_logic_app_workflow.threat_response[0].id : null
}

output "logic_app_endpoint" {
  description = "Endpoint URL of the Logic App"
  value       = var.enable_logic_apps ? azurerm_logic_app_workflow.threat_response[0].access_endpoint : null
  sensitive   = true
}

# Action Group Information
output "action_group_name" {
  description = "Name of the action group for alert notifications"
  value       = azurerm_monitor_action_group.security_team.name
}

output "action_group_id" {
  description = "ID of the action group for alert notifications"
  value       = azurerm_monitor_action_group.security_team.id
}

# Network Watcher Information
output "network_watcher_name" {
  description = "Name of the Network Watcher instance"
  value       = data.azurerm_network_watcher.main.name
}

output "network_watcher_id" {
  description = "ID of the Network Watcher instance"
  value       = data.azurerm_network_watcher.main.id
}

# Monitoring Dashboard Information
output "workbook_dashboard_id" {
  description = "ID of the Azure Monitor Workbook dashboard"
  value       = var.enable_workbook_dashboard ? azurerm_application_insights_workbook.threat_detection[0].id : null
}

# Threat Detection Queries
output "threat_detection_queries" {
  description = "KQL queries for threat detection"
  value = {
    port_scanning = local.port_scanning_query
    data_exfiltration = local.data_exfiltration_query
    failed_connections = local.failed_connections_query
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    resource_group          = azurerm_resource_group.main.name
    location               = azurerm_resource_group.main.location
    storage_account        = azurerm_storage_account.flow_logs.name
    log_analytics_workspace = azurerm_log_analytics_workspace.main.name
    demo_nsg_created       = var.create_demo_nsg
    logic_apps_enabled     = var.enable_logic_apps
    workbook_enabled       = var.enable_workbook_dashboard
    alert_rules_count      = 3
    environment           = var.environment
  }
}

# Security Information
output "security_endpoints" {
  description = "Important security monitoring endpoints"
  value = {
    log_analytics_portal = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/logs"
    storage_account_portal = "https://portal.azure.com/#@/resource${azurerm_storage_account.flow_logs.id}"
    alert_rules_portal = "https://portal.azure.com/#blade/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/alertRules"
    network_watcher_portal = "https://portal.azure.com/#@/resource${data.azurerm_network_watcher.main.id}"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    log_analytics_workspace = "Variable based on data ingestion (~$2-10/GB)"
    storage_account = "~$5-15/month for flow logs storage"
    logic_apps = var.enable_logic_apps ? "~$0.10-1/month based on executions" : "$0 (disabled)"
    alerts = "~$0.10/month per alert rule"
    total_estimated = "~$20-50/month (varies with data volume)"
    note = "Costs depend on data ingestion volume and alert frequency"
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps for configuration and monitoring"
  value = {
    configure_additional_nsgs = "Add more NSGs to flow logs configuration for comprehensive monitoring"
    customize_alert_thresholds = "Adjust alert thresholds based on your environment's baseline"
    setup_automation = "Configure Logic Apps actions for automated incident response"
    monitor_costs = "Monitor Log Analytics costs and adjust retention policies as needed"
    test_alerts = "Test alert rules by generating test traffic patterns"
  }
}