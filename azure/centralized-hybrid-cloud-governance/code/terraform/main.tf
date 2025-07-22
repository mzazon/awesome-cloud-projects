# Data sources for current Azure context
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Generate random suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and tagging
locals {
  suffix = var.use_random_suffix ? random_string.suffix.result : ""
  
  # Naming convention
  resource_group_name         = var.use_random_suffix ? "${var.resource_group_name}-${local.suffix}" : var.resource_group_name
  log_analytics_workspace_name = var.use_random_suffix ? "${var.log_analytics_workspace_name}-${local.suffix}" : var.log_analytics_workspace_name
  arc_k8s_cluster_name       = var.use_random_suffix ? "${var.arc_k8s_cluster_name}-${local.suffix}" : var.arc_k8s_cluster_name
  service_principal_name     = var.use_random_suffix ? "${var.service_principal_name}-${local.suffix}" : var.service_principal_name
  
  # Common tags
  common_tags = merge(
    {
      environment = var.environment
      purpose     = var.purpose
      managed_by  = "terraform"
      created_by  = "azure-arc-governance-recipe"
    },
    var.additional_tags
  )
}

# Resource Group for Arc governance resources
resource "azurerm_resource_group" "arc_governance" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "arc_workspace" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.arc_governance.location
  resource_group_name = azurerm_resource_group.arc_governance.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.common_tags, {
    component = "monitoring"
  })
}

# Service Principal for Arc server onboarding
resource "azuread_application" "arc_onboarding" {
  display_name = local.service_principal_name
  
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
  
  tags = [
    "terraform-managed",
    "azure-arc-onboarding"
  ]
}

resource "azuread_service_principal" "arc_onboarding" {
  application_id = azuread_application.arc_onboarding.application_id
  
  tags = [
    "terraform-managed",
    "azure-arc-onboarding"
  ]
}

resource "azuread_service_principal_password" "arc_onboarding" {
  service_principal_id = azuread_service_principal.arc_onboarding.object_id
  display_name         = "Arc Onboarding Key"
}

# Role assignment for Arc onboarding service principal
resource "azurerm_role_assignment" "arc_onboarding" {
  scope                = azurerm_resource_group.arc_governance.id
  role_definition_name = "Azure Connected Machine Onboarding"
  principal_id         = azuread_service_principal.arc_onboarding.object_id
}

# Data Collection Rule for Arc-enabled servers performance monitoring
resource "azurerm_monitor_data_collection_rule" "arc_servers" {
  count = var.enable_performance_monitoring ? 1 : 0
  
  name                = "dcr-arc-servers-${local.suffix}"
  resource_group_name = azurerm_resource_group.arc_governance.name
  location            = azurerm_resource_group.arc_governance.location
  
  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.arc_workspace.id
      name                  = "centralWorkspace"
    }
  }
  
  data_flow {
    streams      = ["Microsoft-Perf"]
    destinations = ["centralWorkspace"]
  }
  
  data_sources {
    performance_counter {
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = var.performance_counter_sample_rate
      counter_specifiers = [
        "\\Processor(_Total)\\% Processor Time",
        "\\Memory\\Available Bytes",
        "\\LogicalDisk(_Total)\\% Free Space",
        "\\Network Interface(*)\\Bytes Total/sec",
        "\\System\\System Up Time"
      ]
      name = "perfCounterDataSource"
    }
  }
  
  tags = merge(local.common_tags, {
    component = "monitoring"
    type      = "data-collection-rule"
  })
}

# Policy Assignment: Security baseline for Arc-enabled servers
resource "azurerm_resource_policy_assignment" "arc_servers_baseline" {
  count = var.enable_arc_servers_baseline ? 1 : 0
  
  name                 = "arc-servers-baseline"
  display_name         = "Security baseline for Arc-enabled servers"
  scope                = azurerm_resource_group.arc_governance.id
  policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/c96b2f5d-8c94-4588-bb6e-0e1295d5a6d4"
  location             = azurerm_resource_group.arc_governance.location
  enforcement_mode     = var.policy_assignment_enforcement_mode
  
  dynamic "identity" {
    for_each = var.enable_system_assigned_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  metadata = jsonencode({
    category = "Hybrid Governance"
    purpose  = "Arc-enabled servers security baseline"
  })
}

# Role assignment for Arc servers baseline policy
resource "azurerm_role_assignment" "arc_servers_baseline_policy" {
  count = var.enable_arc_servers_baseline && var.enable_system_assigned_identity ? 1 : 0
  
  scope                = azurerm_resource_group.arc_governance.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_resource_policy_assignment.arc_servers_baseline[0].identity[0].principal_id
}

# Policy Assignment: Kubernetes container security
resource "azurerm_resource_policy_assignment" "k8s_container_security" {
  count = var.enable_k8s_container_security ? 1 : 0
  
  name                 = "k8s-container-security"
  display_name         = "Kubernetes container security baseline"
  scope                = azurerm_resource_group.arc_governance.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/95edb821-ddaf-4404-9732-666045e056b4"
  enforcement_mode     = var.policy_assignment_enforcement_mode
  
  parameters = jsonencode({
    effect = {
      value = "audit"
    }
  })
  
  metadata = jsonencode({
    category = "Hybrid Governance"
    purpose  = "Kubernetes container security baseline"
  })
}

# Resource Graph Shared Query for Arc compliance monitoring
resource "azurerm_resource_graph_shared_query" "arc_compliance_status" {
  count = var.create_shared_queries ? 1 : 0
  
  name                = "arc-compliance-status"
  resource_group_name = azurerm_resource_group.arc_governance.name
  location            = azurerm_resource_group.arc_governance.location
  description         = "Monitor compliance status of Arc-enabled resources"
  
  query = "PolicyResources | where type =~ 'microsoft.policyinsights/policystates' | where properties.resourceType contains 'microsoft.hybridcompute' or properties.resourceType contains 'microsoft.kubernetes' | project resourceId=properties.resourceId, complianceState=properties.complianceState, policyDefinitionName=properties.policyDefinitionName, timestamp=properties.timestamp | order by timestamp desc"
  
  tags = merge(local.common_tags, {
    component = "compliance"
    type      = "resource-graph-query"
  })
}

# Resource Graph Shared Query for Arc resource inventory
resource "azurerm_resource_graph_shared_query" "arc_resource_inventory" {
  count = var.create_shared_queries ? 1 : 0
  
  name                = "arc-resource-inventory"
  resource_group_name = azurerm_resource_group.arc_governance.name
  location            = azurerm_resource_group.arc_governance.location
  description         = "Inventory of all Arc-enabled resources"
  
  query = "Resources | where type =~ 'microsoft.hybridcompute/machines' or type =~ 'microsoft.kubernetes/connectedclusters' | project name, type, location, resourceGroup, subscriptionId, properties.status, properties.lastStatusChange | order by type asc"
  
  tags = merge(local.common_tags, {
    component = "inventory"
    type      = "resource-graph-query"
  })
}

# Policy Remediation for Arc servers baseline (created but not started)
resource "azurerm_resource_policy_remediation" "arc_servers_baseline" {
  count = var.enable_arc_servers_baseline ? 1 : 0
  
  name                 = "remediate-arc-servers-baseline"
  scope                = azurerm_resource_group.arc_governance.id
  policy_assignment_id = azurerm_resource_policy_assignment.arc_servers_baseline[0].id
  location_filters     = [var.location]
  
  # Note: This creates the remediation task but doesn't start it
  # Manual intervention or additional automation is needed to start remediation
  
  depends_on = [
    azurerm_role_assignment.arc_servers_baseline_policy
  ]
}

# Custom Role Definition for Arc Management (optional)
resource "azurerm_role_definition" "arc_manager" {
  count = var.create_custom_role_definitions ? 1 : 0
  
  name        = "Arc Resource Manager"
  scope       = data.azurerm_subscription.current.id
  description = "Custom role for managing Arc-enabled resources"
  
  permissions {
    actions = [
      "Microsoft.HybridCompute/machines/read",
      "Microsoft.HybridCompute/machines/write",
      "Microsoft.HybridCompute/machines/delete",
      "Microsoft.HybridCompute/machines/extensions/read",
      "Microsoft.HybridCompute/machines/extensions/write",
      "Microsoft.HybridCompute/machines/extensions/delete",
      "Microsoft.Kubernetes/connectedClusters/read",
      "Microsoft.Kubernetes/connectedClusters/write",
      "Microsoft.Kubernetes/connectedClusters/delete",
      "Microsoft.KubernetesConfiguration/extensions/read",
      "Microsoft.KubernetesConfiguration/extensions/write",
      "Microsoft.KubernetesConfiguration/extensions/delete",
      "Microsoft.Authorization/policyAssignments/read",
      "Microsoft.Authorization/policyAssignments/write",
      "Microsoft.Insights/dataCollectionRules/read",
      "Microsoft.Insights/dataCollectionRules/write",
      "Microsoft.OperationalInsights/workspaces/read",
      "Microsoft.OperationalInsights/workspaces/sharedKeys/action",
      "Microsoft.ResourceGraph/queries/read",
      "Microsoft.ResourceGraph/queries/write"
    ]
    
    not_actions = []
  }
  
  assignable_scopes = [
    data.azurerm_subscription.current.id
  ]
}

# Action Group for monitoring alerts (optional)
resource "azurerm_monitor_action_group" "arc_alerts" {
  name                = "ag-arc-alerts-${local.suffix}"
  resource_group_name = azurerm_resource_group.arc_governance.name
  short_name          = "ArcAlerts"
  
  # Email notification can be configured here
  # email_receiver {
  #   name          = "admin"
  #   email_address = "admin@example.com"
  # }
  
  tags = merge(local.common_tags, {
    component = "alerting"
  })
}

# Scheduled Query Alert for Arc connectivity issues
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "arc_connectivity" {
  name                = "arc-connectivity-alert-${local.suffix}"
  resource_group_name = azurerm_resource_group.arc_governance.name
  location            = azurerm_resource_group.arc_governance.location
  
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_log_analytics_workspace.arc_workspace.id]
  severity             = 3
  
  criteria {
    query = <<-QUERY
      Heartbeat
      | where ResourceProvider == "Microsoft.HybridCompute"
      | summarize LastHeartbeat = max(TimeGenerated) by Computer
      | where LastHeartbeat < ago(10m)
      | count
    QUERY
    
    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
  
  action {
    action_groups = [azurerm_monitor_action_group.arc_alerts.id]
  }
  
  description = "Alert when Arc-enabled servers haven't reported heartbeat in 10 minutes"
  
  tags = merge(local.common_tags, {
    component = "alerting"
    type      = "connectivity-monitoring"
  })
}

# Diagnostic settings for the Log Analytics workspace
resource "azurerm_monitor_diagnostic_setting" "law_diagnostics" {
  name               = "law-diagnostics"
  target_resource_id = azurerm_log_analytics_workspace.arc_workspace.id
  
  # Since we're using the same workspace, we'll create a separate workspace for diagnostics
  # or use a different target like Storage Account or Event Hub
  # For simplicity, we'll comment this out to avoid circular dependency
  # log_analytics_workspace_id = azurerm_log_analytics_workspace.arc_workspace.id
  
  # enabled_log {
  #   category = "Audit"
  # }
  
  # metric {
  #   category = "AllMetrics"
  # }
}