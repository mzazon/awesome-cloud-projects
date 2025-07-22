# Output Values for Azure Policy and Resource Graph Implementation
# This file defines all output values that will be displayed after deployment
# and can be used by other Terraform configurations or scripts

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.governance.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.governance.id
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.governance.location
}

# Policy Definition Information
output "policy_definitions" {
  description = "Information about created policy definitions"
  value = {
    require_department_tag = {
      id           = azurerm_policy_definition.require_department_tag.id
      name         = azurerm_policy_definition.require_department_tag.name
      display_name = azurerm_policy_definition.require_department_tag.display_name
    }
    require_environment_tag = {
      id           = azurerm_policy_definition.require_environment_tag.id
      name         = azurerm_policy_definition.require_environment_tag.name
      display_name = azurerm_policy_definition.require_environment_tag.display_name
    }
    inherit_costcenter_tag = {
      id           = azurerm_policy_definition.inherit_costcenter_tag.id
      name         = azurerm_policy_definition.inherit_costcenter_tag.name
      display_name = azurerm_policy_definition.inherit_costcenter_tag.display_name
    }
  }
}

# Policy Initiative Information
output "policy_initiative" {
  description = "Information about the created policy initiative"
  value = {
    id           = azurerm_policy_set_definition.mandatory_tagging.id
    name         = azurerm_policy_set_definition.mandatory_tagging.name
    display_name = azurerm_policy_set_definition.mandatory_tagging.display_name
    description  = azurerm_policy_set_definition.mandatory_tagging.description
  }
}

# Policy Assignment Information
output "policy_assignment" {
  description = "Information about the created policy assignment"
  value = {
    id                    = azurerm_policy_assignment.mandatory_tagging.id
    name                  = azurerm_policy_assignment.mandatory_tagging.name
    display_name          = azurerm_policy_assignment.mandatory_tagging.display_name
    scope                 = azurerm_policy_assignment.mandatory_tagging.scope
    enforcement_mode      = azurerm_policy_assignment.mandatory_tagging.enforce
    identity_principal_id = azurerm_policy_assignment.mandatory_tagging.identity[0].principal_id
    identity_tenant_id    = azurerm_policy_assignment.mandatory_tagging.identity[0].tenant_id
  }
}

# Policy Remediation Information
output "policy_remediation" {
  description = "Information about created policy remediation tasks"
  value = var.enable_remediation_tasks ? {
    id                         = azurerm_policy_remediation.inherit_costcenter_remediation[0].id
    name                       = azurerm_policy_remediation.inherit_costcenter_remediation[0].name
    policy_assignment_id       = azurerm_policy_remediation.inherit_costcenter_remediation[0].policy_assignment_id
    policy_definition_reference_id = azurerm_policy_remediation.inherit_costcenter_remediation[0].policy_definition_reference_id
    resource_discovery_mode    = azurerm_policy_remediation.inherit_costcenter_remediation[0].resource_discovery_mode
  } : null
}

# Log Analytics Workspace Information
output "log_analytics_workspace" {
  description = "Information about the created Log Analytics workspace"
  value = {
    id                  = azurerm_log_analytics_workspace.governance.id
    name                = azurerm_log_analytics_workspace.governance.name
    workspace_id        = azurerm_log_analytics_workspace.governance.workspace_id
    primary_shared_key  = azurerm_log_analytics_workspace.governance.primary_shared_key
    secondary_shared_key = azurerm_log_analytics_workspace.governance.secondary_shared_key
    retention_in_days   = azurerm_log_analytics_workspace.governance.retention_in_days
  }
  sensitive = true
}

# Application Insights Information
output "application_insights" {
  description = "Information about the created Application Insights instance"
  value = {
    id                = azurerm_application_insights.governance.id
    name              = azurerm_application_insights.governance.name
    app_id            = azurerm_application_insights.governance.app_id
    instrumentation_key = azurerm_application_insights.governance.instrumentation_key
    connection_string = azurerm_application_insights.governance.connection_string
  }
  sensitive = true
}

# Monitoring and Alerting Information
output "monitoring_action_group" {
  description = "Information about the created monitoring action group"
  value = var.enable_monitoring_alerts ? {
    id         = azurerm_monitor_action_group.governance_alerts[0].id
    name       = azurerm_monitor_action_group.governance_alerts[0].name
    short_name = azurerm_monitor_action_group.governance_alerts[0].short_name
  } : null
}

output "policy_violation_alert" {
  description = "Information about the created policy violation alert"
  value = var.enable_monitoring_alerts ? {
    id          = azurerm_monitor_scheduled_query_rules_alert_v2.policy_violations[0].id
    name        = azurerm_monitor_scheduled_query_rules_alert_v2.policy_violations[0].name
    description = azurerm_monitor_scheduled_query_rules_alert_v2.policy_violations[0].description
    severity    = azurerm_monitor_scheduled_query_rules_alert_v2.policy_violations[0].severity
    enabled     = azurerm_monitor_scheduled_query_rules_alert_v2.policy_violations[0].enabled
  } : null
}

# Automation Account Information
output "automation_account" {
  description = "Information about the created automation account"
  value = var.enable_automation_account ? {
    id                = azurerm_automation_account.governance[0].id
    name              = azurerm_automation_account.governance[0].name
    identity_principal_id = azurerm_automation_account.governance[0].identity[0].principal_id
    identity_tenant_id    = azurerm_automation_account.governance[0].identity[0].tenant_id
  } : null
}

output "automation_runbook" {
  description = "Information about the created automation runbook"
  value = var.enable_automation_account ? {
    id          = azurerm_automation_runbook.tag_remediation[0].id
    name        = azurerm_automation_runbook.tag_remediation[0].name
    description = azurerm_automation_runbook.tag_remediation[0].description
    runbook_type = azurerm_automation_runbook.tag_remediation[0].runbook_type
  } : null
}

# Dashboard Information
output "compliance_dashboard" {
  description = "Information about the created compliance dashboard"
  value = var.enable_dashboard ? {
    id   = azurerm_dashboard.compliance[0].id
    name = azurerm_dashboard.compliance[0].name
  } : null
}

# Resource Graph Query Information
output "resource_graph_queries" {
  description = "Information about created Resource Graph queries"
  value = var.enable_resource_graph_queries ? {
    tag_compliance = {
      id          = azurerm_resource_graph_query.tag_compliance[0].id
      name        = azurerm_resource_graph_query.tag_compliance[0].name
      description = azurerm_resource_graph_query.tag_compliance[0].description
    }
    missing_tags = {
      id          = azurerm_resource_graph_query.missing_tags[0].id
      name        = azurerm_resource_graph_query.missing_tags[0].name
      description = azurerm_resource_graph_query.missing_tags[0].description
    }
  } : null
}

# Storage Account Information
output "storage_account" {
  description = "Information about the created storage account"
  value = {
    id                      = azurerm_storage_account.governance.id
    name                    = azurerm_storage_account.governance.name
    primary_access_key      = azurerm_storage_account.governance.primary_access_key
    secondary_access_key    = azurerm_storage_account.governance.secondary_access_key
    primary_connection_string = azurerm_storage_account.governance.primary_connection_string
    secondary_connection_string = azurerm_storage_account.governance.secondary_connection_string
  }
  sensitive = true
}

# Azure CLI Commands for Post-Deployment Operations
output "azure_cli_commands" {
  description = "Useful Azure CLI commands for managing the deployed resources"
  value = {
    # Policy commands
    check_policy_assignment = "az policy assignment show --name ${azurerm_policy_assignment.mandatory_tagging.name} --scope ${azurerm_policy_assignment.mandatory_tagging.scope}"
    check_compliance_status = "az policy state list --policy-assignment ${azurerm_policy_assignment.mandatory_tagging.name}"
    
    # Resource Graph commands
    query_tag_compliance = "az graph query -q \"Resources | where type !in ('microsoft.resources/subscriptions', 'microsoft.resources/resourcegroups') | extend compliance = case(tags.Department != '' and isnotempty(tags.Department) and tags.Environment != '' and isnotempty(tags.Environment) and tags.CostCenter != '' and isnotempty(tags.CostCenter), 'Fully Compliant', tags.Department != '' and isnotempty(tags.Department) or tags.Environment != '' and isnotempty(tags.Environment) or tags.CostCenter != '' and isnotempty(tags.CostCenter), 'Partially Compliant', 'Non-Compliant') | summarize count() by compliance | order by compliance desc\""
    query_missing_tags = "az graph query -q \"Resources | where type !in ('microsoft.resources/subscriptions', 'microsoft.resources/resourcegroups') | where tags.Department == '' or isempty(tags.Department) or tags.Environment == '' or isempty(tags.Environment) or tags.CostCenter == '' or isempty(tags.CostCenter) | project name, type, resourceGroup, location, tags | limit 100\""
    
    # Monitoring commands
    view_policy_logs = "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.governance.workspace_id} --analytics-query 'PolicyInsights | where ComplianceState == \"NonCompliant\" | summarize count() by ResourceType | order by count_ desc' --out table"
    
    # Dashboard commands
    open_dashboard = "az portal dashboard show --name ${var.enable_dashboard ? azurerm_dashboard.compliance[0].name : var.dashboard_name} --resource-group ${azurerm_resource_group.governance.name}"
  }
}

# Subscription and Tenant Information
output "subscription_info" {
  description = "Information about the current subscription and tenant"
  value = {
    subscription_id = data.azurerm_subscription.current.subscription_id
    tenant_id       = data.azurerm_client_config.current.tenant_id
    client_id       = data.azurerm_client_config.current.client_id
  }
}

# Generated Resource Names
output "generated_names" {
  description = "Generated resource names using random suffix"
  value = {
    random_suffix             = random_string.suffix.result
    log_analytics_workspace   = azurerm_log_analytics_workspace.governance.name
    application_insights      = azurerm_application_insights.governance.name
    storage_account          = azurerm_storage_account.governance.name
    automation_account       = var.enable_automation_account ? azurerm_automation_account.governance[0].name : null
    action_group             = var.enable_monitoring_alerts ? azurerm_monitor_action_group.governance_alerts[0].name : null
    alert_rule               = var.enable_monitoring_alerts ? azurerm_monitor_scheduled_query_rules_alert_v2.policy_violations[0].name : null
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    policy_assignment_scope     = var.policy_assignment_scope
    policy_enforcement_mode     = var.policy_enforcement_mode
    required_tags              = var.required_tags
    excluded_resource_types    = var.excluded_resource_types
    monitoring_alerts_enabled  = var.enable_monitoring_alerts
    automation_account_enabled = var.enable_automation_account
    dashboard_enabled          = var.enable_dashboard
    remediation_tasks_enabled  = var.enable_remediation_tasks
    resource_graph_queries_enabled = var.enable_resource_graph_queries
    log_retention_days         = var.log_retention_days
  }
}

# Next Steps and Recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    validation_steps = [
      "1. Verify policy assignment status using: az policy assignment show --name ${azurerm_policy_assignment.mandatory_tagging.name} --scope ${azurerm_policy_assignment.mandatory_tagging.scope}",
      "2. Check compliance status using: az policy state list --policy-assignment ${azurerm_policy_assignment.mandatory_tagging.name}",
      "3. Test tag enforcement by creating a resource without required tags",
      "4. Monitor compliance using Resource Graph queries",
      "5. Review dashboard for compliance insights"
    ]
    monitoring_setup = [
      "1. Configure email addresses in the action group for alert notifications",
      "2. Customize alert thresholds based on your environment",
      "3. Set up additional monitoring queries for specific compliance requirements",
      "4. Configure automated remediation workflows if needed"
    ]
    governance_actions = [
      "1. Review and adjust excluded resource types based on your organization's needs",
      "2. Customize tag values and validation rules",
      "3. Implement additional policy definitions for specific compliance requirements",
      "4. Set up regular compliance reporting workflows",
      "5. Train teams on tagging standards and compliance requirements"
    ]
  }
}

# Important Notes
output "important_notes" {
  description = "Important notes and considerations for the deployed solution"
  value = {
    security_considerations = [
      "Policy assignment uses system-assigned managed identity with Contributor permissions",
      "Automation account uses system-assigned managed identity for remediation tasks",
      "Log Analytics workspace contains sensitive compliance data - ensure proper access controls",
      "Storage account contains automation logs - review access permissions regularly"
    ]
    cost_considerations = [
      "Log Analytics workspace charges based on data ingestion and retention",
      "Application Insights charges based on data volume and features used",
      "Azure Automation charges per job execution minute",
      "Storage account charges for log storage and transactions"
    ]
    operational_notes = [
      "Policy evaluation may take up to 30 minutes for new assignments",
      "Remediation tasks run based on compliance evaluation schedules",
      "Dashboard refresh intervals depend on underlying data sources",
      "Resource Graph queries are cached and may have slight delays"
    ]
  }
}