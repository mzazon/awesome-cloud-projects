# Output values for Azure health monitoring infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.health_monitoring.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.health_monitoring.location
}

# Service Bus Information
output "servicebus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.health_monitoring.name
}

output "servicebus_namespace_id" {
  description = "Resource ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.health_monitoring.id
}

output "servicebus_primary_connection_string" {
  description = "Primary connection string for Service Bus namespace"
  value       = azurerm_servicebus_namespace_authorization_rule.health_monitoring.primary_connection_string
  sensitive   = true
}

output "servicebus_secondary_connection_string" {
  description = "Secondary connection string for Service Bus namespace"
  value       = azurerm_servicebus_namespace_authorization_rule.health_monitoring.secondary_connection_string
  sensitive   = true
}

output "health_events_queue_name" {
  description = "Name of the health events queue"
  value       = azurerm_servicebus_queue.health_events.name
}

output "remediation_actions_topic_name" {
  description = "Name of the remediation actions topic"
  value       = azurerm_servicebus_topic.remediation_actions.name
}

# Service Bus Subscription Information
output "auto_scale_subscription_name" {
  description = "Name of the auto-scale handler subscription"
  value       = azurerm_servicebus_subscription.auto_scale_handler.name
}

output "restart_handler_subscription_name" {
  description = "Name of the restart handler subscription"
  value       = azurerm_servicebus_subscription.restart_handler.name
}

output "webhook_notifications_subscription_name" {
  description = "Name of the webhook notifications subscription"
  value       = azurerm_servicebus_subscription.webhook_notifications.name
}

# Logic Apps Information
output "health_orchestrator_logic_app_name" {
  description = "Name of the health orchestrator Logic App"
  value       = azurerm_logic_app_workflow.health_orchestrator.name
}

output "health_orchestrator_logic_app_id" {
  description = "Resource ID of the health orchestrator Logic App"
  value       = azurerm_logic_app_workflow.health_orchestrator.id
}

output "restart_handler_logic_app_name" {
  description = "Name of the restart handler Logic App"
  value       = azurerm_logic_app_workflow.restart_handler.name
}

output "restart_handler_logic_app_id" {
  description = "Resource ID of the restart handler Logic App"
  value       = azurerm_logic_app_workflow.restart_handler.id
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.health_monitoring.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.health_monitoring.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (GUID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.health_monitoring.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.health_monitoring.primary_shared_key
  sensitive   = true
}

output "action_group_name" {
  description = "Name of the action group for health alerts"
  value       = azurerm_monitor_action_group.health_alerts.name
}

output "action_group_id" {
  description = "Resource ID of the action group"
  value       = azurerm_monitor_action_group.health_alerts.id
}

# Demo VM Information (conditional outputs)
output "demo_vm_name" {
  description = "Name of the demo VM (if created)"
  value       = var.create_demo_vm ? azurerm_linux_virtual_machine.demo[0].name : null
}

output "demo_vm_id" {
  description = "Resource ID of the demo VM (if created)"
  value       = var.create_demo_vm ? azurerm_linux_virtual_machine.demo[0].id : null
}

output "demo_vm_private_ip" {
  description = "Private IP address of the demo VM (if created)"
  value       = var.create_demo_vm ? azurerm_network_interface.demo[0].private_ip_address : null
}

output "demo_vm_ssh_private_key" {
  description = "SSH private key for demo VM access (if created)"
  value       = var.create_demo_vm ? tls_private_key.demo[0].private_key_pem : null
  sensitive   = true
}

output "demo_vm_ssh_public_key" {
  description = "SSH public key for demo VM (if created)"
  value       = var.create_demo_vm ? tls_private_key.demo[0].public_key_openssh : null
}

output "demo_vm_health_alert_name" {
  description = "Name of the VM health alert (if created)"
  value       = var.create_demo_vm ? azurerm_monitor_activity_log_alert.vm_health[0].name : null
}

# Connection and Integration Information
output "servicebus_api_connection_name" {
  description = "Name of the Service Bus API connection for Logic Apps"
  value       = azurerm_api_connection.servicebus.name
}

output "servicebus_api_connection_id" {
  description = "Resource ID of the Service Bus API connection"
  value       = azurerm_api_connection.servicebus.id
}

# Diagnostic Settings Information
output "servicebus_diagnostic_setting_name" {
  description = "Name of the Service Bus diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.servicebus.name
}

output "logic_app_orchestrator_diagnostic_setting_name" {
  description = "Name of the Logic App orchestrator diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.logic_app_orchestrator.name
}

output "logic_app_restart_diagnostic_setting_name" {
  description = "Name of the Logic App restart handler diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.logic_app_restart.name
}

# Useful URLs and Endpoints
output "azure_portal_resource_group_url" {
  description = "Azure portal URL for the resource group"
  value       = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.health_monitoring.name}"
}

output "azure_portal_servicebus_url" {
  description = "Azure portal URL for the Service Bus namespace"
  value       = "https://portal.azure.com/#@/resource${azurerm_servicebus_namespace.health_monitoring.id}"
}

output "azure_portal_log_analytics_url" {
  description = "Azure portal URL for the Log Analytics workspace"
  value       = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.health_monitoring.id}"
}

# Random suffix for reference
output "random_suffix" {
  description = "Random suffix used in resource naming"
  value       = random_string.suffix.result
}

# Environment information
output "environment" {
  description = "Environment name used for this deployment"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for this deployment"
  value       = var.project_name
}