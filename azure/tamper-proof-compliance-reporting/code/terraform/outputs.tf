# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.compliance.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.compliance.id
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.compliance.location
}

# Confidential Ledger Outputs
output "confidential_ledger_name" {
  description = "Name of the Azure Confidential Ledger"
  value       = azurerm_confidential_ledger.compliance.name
}

output "confidential_ledger_id" {
  description = "ID of the Azure Confidential Ledger"
  value       = azurerm_confidential_ledger.compliance.id
}

output "confidential_ledger_uri" {
  description = "URI endpoint for the Confidential Ledger"
  value       = azurerm_confidential_ledger.compliance.ledger_uri
  sensitive   = false
}

output "confidential_ledger_identity_service_uri" {
  description = "Identity service URI for the Confidential Ledger"
  value       = azurerm_confidential_ledger.compliance.identity_service_uri
  sensitive   = false
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.compliance.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.compliance.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.compliance.primary_blob_endpoint
  sensitive   = false
}

output "compliance_container_name" {
  description = "Name of the compliance reports container"
  value       = azurerm_storage_container.compliance_reports.name
}

output "compliance_container_url" {
  description = "URL of the compliance reports container"
  value       = "${azurerm_storage_account.compliance.primary_blob_endpoint}${azurerm_storage_container.compliance_reports.name}"
  sensitive   = false
}

# Logic App Outputs
output "logic_app_name" {
  description = "Name of the Logic App"
  value       = azurerm_logic_app_workflow.compliance.name
}

output "logic_app_id" {
  description = "ID of the Logic App"
  value       = azurerm_logic_app_workflow.compliance.id
}

output "logic_app_trigger_url" {
  description = "HTTP trigger URL for the Logic App"
  value       = azurerm_logic_app_trigger_http_request.compliance_trigger.callback_url
  sensitive   = true
}

output "logic_app_principal_id" {
  description = "Principal ID of the Logic App managed identity"
  value       = azurerm_logic_app_workflow.compliance.identity[0].principal_id
}

# Log Analytics Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.compliance.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.compliance.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (Workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.compliance.workspace_id
  sensitive   = false
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.compliance.primary_shared_key
  sensitive   = true
}

# Monitoring and Alerting Outputs
output "action_group_name" {
  description = "Name of the action group"
  value       = azurerm_monitor_action_group.compliance.name
}

output "action_group_id" {
  description = "ID of the action group"
  value       = azurerm_monitor_action_group.compliance.id
}

output "metric_alert_name" {
  description = "Name of the CPU metric alert"
  value       = azurerm_monitor_metric_alert.cpu_compliance.name
}

output "scheduled_query_alert_name" {
  description = "Name of the security events scheduled query alert"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.security_events.name
}

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.compliance.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.compliance.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.compliance.connection_string
  sensitive   = true
}

# Networking Outputs
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.compliance.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.compliance.id
}

output "subnet_name" {
  description = "Name of the compliance subnet"
  value       = azurerm_subnet.compliance.name
}

output "subnet_id" {
  description = "ID of the compliance subnet"
  value       = azurerm_subnet.compliance.id
}

output "private_endpoint_storage_ip" {
  description = "Private IP address of the storage account private endpoint"
  value       = azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address
  sensitive   = false
}

# Security Outputs
output "network_security_group_name" {
  description = "Name of the network security group"
  value       = azurerm_network_security_group.compliance.name
}

output "network_security_group_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.compliance.id
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed compliance infrastructure"
  value = {
    resource_group_name           = azurerm_resource_group.compliance.name
    confidential_ledger_name      = azurerm_confidential_ledger.compliance.name
    logic_app_name               = azurerm_logic_app_workflow.compliance.name
    storage_account_name         = azurerm_storage_account.compliance.name
    log_analytics_workspace_name = azurerm_log_analytics_workspace.compliance.name
    location                     = azurerm_resource_group.compliance.location
    environment                  = var.environment
    project_name                 = var.project_name
  }
}

# Configuration for next steps
output "next_steps" {
  description = "Next steps to configure the compliance system"
  value = {
    step_1 = "Configure Logic App workflow connections to Azure services"
    step_2 = "Set up custom alert rules for specific compliance requirements"
    step_3 = "Configure Azure AD users/groups for Confidential Ledger access"
    step_4 = "Test the end-to-end compliance reporting workflow"
    step_5 = "Review and adjust monitoring thresholds based on your requirements"
  }
}

# Connection strings and endpoints for integration
output "integration_endpoints" {
  description = "Key endpoints for integrating with the compliance system"
  value = {
    confidential_ledger_endpoint = azurerm_confidential_ledger.compliance.ledger_uri
    logic_app_trigger_endpoint  = "Available in sensitive outputs (see logic_app_trigger_url)"
    storage_blob_endpoint       = azurerm_storage_account.compliance.primary_blob_endpoint
    log_analytics_workspace_id  = azurerm_log_analytics_workspace.compliance.workspace_id
  }
  sensitive = false
}

# Cost estimation information
output "cost_estimation_notes" {
  description = "Notes about ongoing costs for the compliance infrastructure"
  value = {
    confidential_ledger = "~$3/day for Private ledger instance"
    storage_account     = "Based on data stored and transactions"
    logic_app          = "Based on workflow executions and actions"
    log_analytics      = "Based on data ingestion and retention"
    monitoring         = "Alert rules and action groups have minimal cost"
    note               = "Actual costs depend on usage patterns and data volume"
  }
}