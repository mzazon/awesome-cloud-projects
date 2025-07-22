# Main Terraform configuration for Azure sustainable workload optimization

# Generate random suffix for resource names to ensure uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and tagging
locals {
  # Generate consistent resource suffix
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_string.suffix.result
  
  # Common resource naming convention
  resource_names = {
    resource_group     = "${var.resource_group_name}-${local.resource_suffix}"
    log_analytics     = "law-${var.project_name}-${local.resource_suffix}"
    automation_account = "aa-${var.project_name}-${local.resource_suffix}"
    action_group      = "ag-${var.project_name}-${local.resource_suffix}"
    workbook          = "wb-${var.project_name}-${local.resource_suffix}"
  }
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Environment        = var.environment
      Project           = var.project_name
      Purpose           = "sustainability"
      ManagedBy         = "terraform"
      AutomationType    = "carbon-optimization"
      CarbonOptimization = "enabled"
      CreatedDate       = formatdate("YYYY-MM-DD", timestamp())
    },
    var.tags
  )
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Data source to get current subscription
data "azurerm_subscription" "current" {}

# Create the main resource group for carbon optimization resources
resource "azurerm_resource_group" "carbon_optimization" {
  name     = local.resource_names.resource_group
  location = var.location
  
  tags = local.common_tags
}

# Create Log Analytics workspace for carbon optimization monitoring
resource "azurerm_log_analytics_workspace" "carbon_optimization" {
  name                = local.resource_names.log_analytics
  location            = azurerm_resource_group.carbon_optimization.location
  resource_group_name = azurerm_resource_group.carbon_optimization.name
  
  # Configure workspace settings
  sku               = var.log_analytics_workspace_sku
  retention_in_days = var.log_analytics_retention_days
  
  # Enable advanced analytics features
  daily_quota_gb                     = -1  # Unlimited
  internet_ingestion_enabled         = true
  internet_query_enabled             = true
  reservation_capacity_in_gb_per_day = null
  
  tags = local.common_tags
}

# Create Azure Automation account for carbon optimization automation
resource "azurerm_automation_account" "carbon_optimization" {
  name                = local.resource_names.automation_account
  location            = azurerm_resource_group.carbon_optimization.location
  resource_group_name = azurerm_resource_group.carbon_optimization.name
  
  # Configure automation account settings
  sku_name = var.automation_account_sku
  
  # Enable system-assigned managed identity for secure authentication
  identity {
    type = "SystemAssigned"
  }
  
  # Enable advanced automation features
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# Create role assignment for Carbon Optimization Reader role
resource "azurerm_role_assignment" "carbon_optimization_reader" {
  count = var.enable_rbac ? 1 : 0
  
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"  # Using Reader role as Carbon Optimization Reader may not be available in all regions
  principal_id         = azurerm_automation_account.carbon_optimization.identity[0].principal_id
  
  depends_on = [azurerm_automation_account.carbon_optimization]
}

# Create role assignment for Contributor role to enable resource management
resource "azurerm_role_assignment" "automation_contributor" {
  count = var.enable_automation ? 1 : 0
  
  scope                = azurerm_resource_group.carbon_optimization.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.carbon_optimization.identity[0].principal_id
  
  depends_on = [azurerm_automation_account.carbon_optimization]
}

# Create PowerShell runbook for carbon monitoring
resource "azurerm_automation_runbook" "carbon_monitoring" {
  count = var.enable_automation ? 1 : 0
  
  name                    = "CarbonOptimizationMonitoring"
  location                = azurerm_resource_group.carbon_optimization.location
  resource_group_name     = azurerm_resource_group.carbon_optimization.name
  automation_account_name = azurerm_automation_account.carbon_optimization.name
  
  # Configure runbook settings
  log_verbose  = true
  log_progress = true
  description  = "Monitor carbon emissions and generate optimization recommendations"
  runbook_type = "PowerShell"
  
  # PowerShell script content for carbon monitoring
  content = templatefile("${path.module}/scripts/carbon-monitoring.ps1", {
    subscription_id = data.azurerm_subscription.current.subscription_id
    workspace_id    = azurerm_log_analytics_workspace.carbon_optimization.workspace_id
    threshold       = var.carbon_optimization_threshold
  })
  
  tags = local.common_tags
  
  depends_on = [azurerm_automation_account.carbon_optimization]
}

# Create PowerShell runbook for automated remediation
resource "azurerm_automation_runbook" "automated_remediation" {
  count = var.enable_automation ? 1 : 0
  
  name                    = "AutomatedCarbonRemediation"
  location                = azurerm_resource_group.carbon_optimization.location
  resource_group_name     = azurerm_resource_group.carbon_optimization.name
  automation_account_name = azurerm_automation_account.carbon_optimization.name
  
  # Configure runbook settings
  log_verbose  = true
  log_progress = true
  description  = "Automated remediation for carbon optimization recommendations"
  runbook_type = "PowerShell"
  
  # PowerShell script content for automated remediation
  content = templatefile("${path.module}/scripts/automated-remediation.ps1", {
    subscription_id = data.azurerm_subscription.current.subscription_id
    resource_group  = azurerm_resource_group.carbon_optimization.name
  })
  
  tags = local.common_tags
  
  depends_on = [azurerm_automation_account.carbon_optimization]
}

# Create schedule for daily carbon monitoring
resource "azurerm_automation_schedule" "daily_monitoring" {
  count = var.enable_automation ? 1 : 0
  
  name                    = "DailyCarbonMonitoring"
  resource_group_name     = azurerm_resource_group.carbon_optimization.name
  automation_account_name = azurerm_automation_account.carbon_optimization.name
  
  # Configure schedule settings
  frequency   = var.monitoring_schedule_frequency
  interval    = var.monitoring_schedule_interval
  description = "Daily carbon optimization monitoring schedule"
  
  # Start time set to 6 AM UTC tomorrow
  start_time = formatdate("YYYY-MM-DD'T'06:00:00Z", timeadd(timestamp(), "24h"))
  
  depends_on = [azurerm_automation_account.carbon_optimization]
}

# Create job schedule to link runbook with schedule
resource "azurerm_automation_job_schedule" "carbon_monitoring_schedule" {
  count = var.enable_automation ? 1 : 0
  
  resource_group_name     = azurerm_resource_group.carbon_optimization.name
  automation_account_name = azurerm_automation_account.carbon_optimization.name
  schedule_name           = azurerm_automation_schedule.daily_monitoring[0].name
  runbook_name            = azurerm_automation_runbook.carbon_monitoring[0].name
  
  # Pass parameters to the runbook
  parameters = {
    SubscriptionId = data.azurerm_subscription.current.subscription_id
    WorkspaceId    = azurerm_log_analytics_workspace.carbon_optimization.workspace_id
  }
  
  depends_on = [
    azurerm_automation_runbook.carbon_monitoring,
    azurerm_automation_schedule.daily_monitoring
  ]
}

# Create action group for carbon optimization alerts
resource "azurerm_monitor_action_group" "carbon_optimization" {
  count = var.enable_alerts ? 1 : 0
  
  name                = local.resource_names.action_group
  resource_group_name = azurerm_resource_group.carbon_optimization.name
  short_name          = "CarbonOpt"
  
  # Configure email notification
  email_receiver {
    name                    = "admin-email"
    email_address           = var.admin_email
    use_common_alert_schema = true
  }
  
  # Configure webhook notification if Slack URL is provided
  dynamic "webhook_receiver" {
    for_each = var.slack_webhook_url != "" ? [1] : []
    content {
      name                    = "slack-webhook"
      service_uri             = var.slack_webhook_url
      use_common_alert_schema = true
    }
  }
  
  # Configure automation runbook action
  dynamic "automation_runbook_receiver" {
    for_each = var.enable_automation ? [1] : []
    content {
      name                    = "carbon-remediation"
      automation_account_id   = azurerm_automation_account.carbon_optimization.id
      runbook_name            = azurerm_automation_runbook.automated_remediation[0].name
      webhook_resource_id     = azurerm_automation_account.carbon_optimization.id
      is_global_runbook       = false
      use_common_alert_schema = true
    }
  }
  
  tags = local.common_tags
}

# Create metric alert for high carbon impact
resource "azurerm_monitor_metric_alert" "high_carbon_impact" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "HighCarbonImpactAlert"
  resource_group_name = azurerm_resource_group.carbon_optimization.name
  
  # Configure alert settings
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Alert when carbon emissions exceed threshold"
  frequency           = "PT5M"
  window_size         = "PT15M"
  severity            = 2
  enabled             = true
  auto_mitigate       = true
  
  # Configure alert criteria (using a proxy metric since carbon emissions may not be directly available)
  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "CPU Credits Consumed"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.carbon_optimization_threshold
    
    dimension {
      name     = "VMName"
      operator = "Include"
      values   = ["*"]
    }
  }
  
  # Configure alert action
  action {
    action_group_id = azurerm_monitor_action_group.carbon_optimization[0].id
  }
  
  tags = local.common_tags
  
  depends_on = [azurerm_monitor_action_group.carbon_optimization]
}

# Create scheduled query rule for carbon optimization opportunities
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "carbon_optimization_opportunities" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "CarbonOptimizationOpportunities"
  resource_group_name = azurerm_resource_group.carbon_optimization.name
  location            = azurerm_resource_group.carbon_optimization.location
  
  # Configure alert settings
  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [azurerm_log_analytics_workspace.carbon_optimization.id]
  severity             = 3
  enabled              = true
  description          = "Alert for carbon optimization opportunities"
  
  # Configure query criteria
  criteria {
    query = "CarbonOptimization_CL | where CarbonSavingsEstimate_d > 50 | count"
    
    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
  
  # Configure alert action
  action {
    action_groups = [azurerm_monitor_action_group.carbon_optimization[0].id]
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_log_analytics_workspace.carbon_optimization,
    azurerm_monitor_action_group.carbon_optimization
  ]
}

# Create Azure Monitor Workbook for carbon optimization dashboard
resource "azurerm_application_insights_workbook" "carbon_optimization" {
  count = var.enable_workbook ? 1 : 0
  
  name                = local.resource_names.workbook
  resource_group_name = azurerm_resource_group.carbon_optimization.name
  location            = azurerm_resource_group.carbon_optimization.location
  
  # Configure workbook settings
  display_name    = "Carbon Optimization Dashboard"
  description     = "Comprehensive carbon optimization monitoring and insights"
  data_json       = templatefile("${path.module}/templates/carbon-workbook.json", {
    workspace_id = azurerm_log_analytics_workspace.carbon_optimization.id
    subscription_id = data.azurerm_subscription.current.subscription_id
  })
  
  tags = local.common_tags
  
  depends_on = [azurerm_log_analytics_workspace.carbon_optimization]
}

# Create diagnostic settings for comprehensive monitoring
resource "azurerm_monitor_diagnostic_setting" "automation_account" {
  name                       = "automation-diagnostics"
  target_resource_id         = azurerm_automation_account.carbon_optimization.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.carbon_optimization.id
  
  # Enable all available log categories
  enabled_log {
    category = "JobLogs"
  }
  
  enabled_log {
    category = "JobStreams"
  }
  
  enabled_log {
    category = "DscNodeStatus"
  }
  
  # Enable all available metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
  
  depends_on = [
    azurerm_automation_account.carbon_optimization,
    azurerm_log_analytics_workspace.carbon_optimization
  ]
}

# Create Log Analytics solutions for enhanced monitoring
resource "azurerm_log_analytics_solution" "automation" {
  solution_name         = "AzureAutomation"
  location              = azurerm_resource_group.carbon_optimization.location
  resource_group_name   = azurerm_resource_group.carbon_optimization.name
  workspace_resource_id = azurerm_log_analytics_workspace.carbon_optimization.id
  workspace_name        = azurerm_log_analytics_workspace.carbon_optimization.name
  
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/AzureAutomation"
  }
  
  depends_on = [azurerm_log_analytics_workspace.carbon_optimization]
}

# Create custom log analytics queries for carbon optimization
resource "azurerm_log_analytics_saved_search" "carbon_optimization_summary" {
  name                       = "CarbonOptimizationSummary"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.carbon_optimization.id
  
  category     = "Carbon Optimization"
  display_name = "Carbon Optimization Summary"
  
  query = <<-QUERY
    CarbonOptimization_CL
    | where TimeGenerated >= ago(30d)
    | summarize 
        TotalRecommendations = count(),
        TotalCarbonSavings = sum(CarbonSavingsEstimate_d),
        AvgCarbonSavings = avg(CarbonSavingsEstimate_d)
    by bin(TimeGenerated, 1d)
    | render timechart
  QUERY
  
  depends_on = [azurerm_log_analytics_workspace.carbon_optimization]
}

resource "azurerm_log_analytics_saved_search" "carbon_optimization_by_category" {
  name                       = "CarbonOptimizationByCategory"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.carbon_optimization.id
  
  category     = "Carbon Optimization"
  display_name = "Carbon Optimization by Category"
  
  query = <<-QUERY
    CarbonOptimization_CL
    | where TimeGenerated >= ago(7d)
    | summarize 
        Count = count(),
        TotalSavings = sum(CarbonSavingsEstimate_d)
    by Category_s
    | order by TotalSavings desc
  QUERY
  
  depends_on = [azurerm_log_analytics_workspace.carbon_optimization]
}