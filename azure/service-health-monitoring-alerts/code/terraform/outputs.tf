# Output Values for Azure Service Health Monitoring Solution
# These outputs provide important information about the created resources

output "resource_group_name" {
  description = "Name of the resource group containing service health monitoring resources"
  value       = azurerm_resource_group.service_health.name
}

output "resource_group_id" {
  description = "Resource ID of the service health monitoring resource group"
  value       = azurerm_resource_group.service_health.id
}

output "action_group_name" {
  description = "Name of the action group for service health notifications"
  value       = azurerm_monitor_action_group.service_health_alerts.name
}

output "action_group_id" {
  description = "Resource ID of the service health action group"
  value       = azurerm_monitor_action_group.service_health_alerts.id
}

output "action_group_short_name" {
  description = "Short name of the action group used in notifications"
  value       = azurerm_monitor_action_group.service_health_alerts.short_name
}

output "notification_email" {
  description = "Email address configured for service health notifications"
  value       = var.notification_email
  sensitive   = true
}

output "notification_phone" {
  description = "Phone number configured for SMS notifications (if provided)"
  value       = var.notification_phone != "" ? var.notification_phone : "Not configured"
  sensitive   = true
}

# Alert Rule Outputs
output "service_issues_alert_id" {
  description = "Resource ID of the service issues alert rule"
  value       = var.enable_service_issues_alert ? azurerm_monitor_activity_log_alert.service_issues[0].id : "Not enabled"
}

output "planned_maintenance_alert_id" {
  description = "Resource ID of the planned maintenance alert rule"
  value       = var.enable_planned_maintenance_alert ? azurerm_monitor_activity_log_alert.planned_maintenance[0].id : "Not enabled"
}

output "health_advisory_alert_id" {
  description = "Resource ID of the health advisory alert rule"
  value       = var.enable_health_advisory_alert ? azurerm_monitor_activity_log_alert.health_advisory[0].id : "Not enabled"
}

output "security_advisory_alert_id" {
  description = "Resource ID of the security advisory alert rule"
  value       = var.enable_security_advisory_alert ? azurerm_monitor_activity_log_alert.security_advisory[0].id : "Not enabled"
}

output "comprehensive_alert_id" {
  description = "Resource ID of the comprehensive service health alert rule"
  value       = azurerm_monitor_activity_log_alert.comprehensive_service_health.id
}

# Summary Information
output "enabled_alert_rules" {
  description = "List of enabled alert rule types"
  value = concat(
    var.enable_service_issues_alert ? ["Service Issues"] : [],
    var.enable_planned_maintenance_alert ? ["Planned Maintenance"] : [],
    var.enable_health_advisory_alert ? ["Health Advisory"] : [],
    var.enable_security_advisory_alert ? ["Security Advisory"] : [],
    ["Comprehensive Service Health"]
  )
}

output "alert_rule_count" {
  description = "Total number of alert rules created"
  value = (
    (var.enable_service_issues_alert ? 1 : 0) +
    (var.enable_planned_maintenance_alert ? 1 : 0) +
    (var.enable_health_advisory_alert ? 1 : 0) +
    (var.enable_security_advisory_alert ? 1 : 0) +
    1  # Comprehensive alert is always enabled
  )
}

output "monitoring_scope" {
  description = "Subscription ID being monitored for service health events"
  value       = data.azurerm_subscription.current.id
}

output "subscription_display_name" {
  description = "Display name of the monitored subscription"
  value       = data.azurerm_subscription.current.display_name
}

# Deployment Information
output "deployment_region" {
  description = "Azure region where monitoring resources were deployed"
  value       = azurerm_resource_group.service_health.location
}

output "resource_tags" {
  description = "Tags applied to the monitoring resources"
  value       = azurerm_resource_group.service_health.tags
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Validation and Testing Outputs
output "action_group_test_command" {
  description = "Azure CLI command to test the action group notifications"
  value = "az monitor action-group test-notifications create --action-group-name '${azurerm_monitor_action_group.service_health_alerts.name}' --resource-group '${azurerm_resource_group.service_health.name}' --alert-type servicehealth"
}

output "alert_rules_list_command" {
  description = "Azure CLI command to list all created alert rules"
  value = "az monitor activity-log alert list --resource-group '${azurerm_resource_group.service_health.name}' --output table"
}

output "service_health_dashboard_url" {
  description = "URL to Azure Service Health dashboard for the subscription"
  value = "https://portal.azure.com/#blade/Microsoft_Azure_Health/AzureHealthBrowseBlade/serviceIssues"
}