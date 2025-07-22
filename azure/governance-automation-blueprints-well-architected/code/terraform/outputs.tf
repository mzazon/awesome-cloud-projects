# Outputs for Azure Governance Automation with Blueprints

output "resource_group_name" {
  description = "Name of the governance resource group"
  value       = azurerm_resource_group.governance.name
}

output "resource_group_id" {
  description = "ID of the governance resource group"
  value       = azurerm_resource_group.governance.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.governance.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.governance.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.governance.workspace_id
}

output "blueprint_name" {
  description = "Name of the Azure Blueprint"
  value       = azurerm_blueprint.enterprise_governance.name
}

output "blueprint_id" {
  description = "ID of the Azure Blueprint"
  value       = azurerm_blueprint.enterprise_governance.id
}

output "blueprint_version" {
  description = "Published version of the blueprint"
  value       = azurerm_blueprint_published_version.v1.version
}

output "blueprint_assignment_name" {
  description = "Name of the blueprint assignment"
  value       = azurerm_blueprint_assignment.enterprise_governance.name
}

output "blueprint_assignment_id" {
  description = "ID of the blueprint assignment"
  value       = azurerm_blueprint_assignment.enterprise_governance.id
}

output "custom_policy_definition_id" {
  description = "ID of the custom policy definition for required tags"
  value       = azurerm_policy_definition.require_tags.id
}

output "policy_initiative_id" {
  description = "ID of the enterprise security policy initiative"
  value       = azurerm_policy_set_definition.enterprise_security.id
}

output "action_group_id" {
  description = "ID of the governance alerts action group"
  value       = var.enable_advisor_alerts ? azurerm_monitor_action_group.governance_alerts[0].id : null
}

output "governance_dashboard_id" {
  description = "ID of the governance monitoring dashboard"
  value       = var.enable_governance_dashboard ? azurerm_portal_dashboard.governance_dashboard[0].id : null
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.governance.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.governance.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.governance.connection_string
  sensitive   = true
}

output "subscription_id" {
  description = "ID of the current subscription"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "ID of the current tenant"
  value       = data.azurerm_client_config.current.tenant_id
}

output "current_user_object_id" {
  description = "Object ID of the current user"
  value       = data.azuread_user.current.object_id
}

output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

output "governance_tags" {
  description = "Common tags applied to governance resources"
  value       = var.governance_tags
}

output "required_tags" {
  description = "List of required tags enforced by policies"
  value       = var.required_tags
}

output "governance_email" {
  description = "Email address for governance team notifications"
  value       = var.governance_email
}

output "deployment_summary" {
  description = "Summary of deployed governance resources"
  value = {
    resource_group_name           = azurerm_resource_group.governance.name
    log_analytics_workspace_name = azurerm_log_analytics_workspace.governance.name
    blueprint_name               = azurerm_blueprint.enterprise_governance.name
    blueprint_version            = azurerm_blueprint_published_version.v1.version
    blueprint_assignment_name    = azurerm_blueprint_assignment.enterprise_governance.name
    policy_initiative_name       = azurerm_policy_set_definition.enterprise_security.name
    custom_policy_name           = azurerm_policy_definition.require_tags.name
    advisor_alerts_enabled       = var.enable_advisor_alerts
    governance_dashboard_enabled = var.enable_governance_dashboard
    location                     = var.location
    environment                  = var.environment
  }
}

output "validation_commands" {
  description = "Commands to validate the governance deployment"
  value = {
    check_blueprint_assignment = "az blueprint assignment show --name ${azurerm_blueprint_assignment.enterprise_governance.name} --subscription ${data.azurerm_subscription.current.subscription_id}"
    list_policy_assignments    = "az policy assignment list --subscription ${data.azurerm_subscription.current.subscription_id}"
    check_policy_compliance    = "az policy state list --subscription ${data.azurerm_subscription.current.subscription_id} --resource-group ${azurerm_resource_group.governance.name}"
    view_advisor_recommendations = "az advisor recommendation list --subscription ${data.azurerm_subscription.current.subscription_id} --category Security"
  }
}

output "cleanup_commands" {
  description = "Commands to clean up governance resources"
  value = {
    delete_blueprint_assignment = "az blueprint assignment delete --name ${azurerm_blueprint_assignment.enterprise_governance.name} --subscription ${data.azurerm_subscription.current.subscription_id} --yes"
    delete_policy_initiative    = "az policy set-definition delete --name ${azurerm_policy_set_definition.enterprise_security.name} --subscription ${data.azurerm_subscription.current.subscription_id}"
    delete_custom_policy        = "az policy definition delete --name ${azurerm_policy_definition.require_tags.name} --subscription ${data.azurerm_subscription.current.subscription_id}"
    delete_blueprint            = "az blueprint delete --name ${azurerm_blueprint.enterprise_governance.name} --subscription ${data.azurerm_subscription.current.subscription_id} --yes"
    delete_resource_group       = "az group delete --name ${azurerm_resource_group.governance.name} --yes --no-wait"
  }
}