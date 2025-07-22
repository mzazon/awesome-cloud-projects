# Main Terraform configuration for Azure Network Threat Detection
# This configuration implements automated network threat detection using Azure Network Watcher and Log Analytics

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local variables for consistent naming and configuration
locals {
  # Resource naming with random suffix
  resource_prefix = "ntd-${random_id.suffix.hex}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment           = var.environment
    Purpose              = "network-security"
    Solution             = "threat-detection"
    ManagedBy           = "terraform"
    CreatedDate         = timestamp()
    LastUpdated         = timestamp()
    SecurityClassification = "sensitive"
    CostCenter          = "security-operations"
  }, var.additional_tags)
  
  # Network Watcher name based on location
  network_watcher_name = var.network_watcher_name != null ? var.network_watcher_name : "NetworkWatcher_${replace(var.location, " ", "")}"
  
  # KQL Queries for threat detection
  port_scanning_query = <<-EOT
    AzureNetworkAnalytics_CL
    | where TimeGenerated > ago(1h)
    | where FlowStatus_s == "D"
    | summarize DestPorts = dcount(DestPort_d), FlowCount = count() by SrcIP_s, bin(TimeGenerated, 5m)
    | where DestPorts > ${var.port_scan_threshold} and FlowCount > ${var.port_scan_flow_count_threshold}
    | project TimeGenerated, SrcIP_s, DestPorts, FlowCount, ThreatLevel = "High"
  EOT
  
  data_exfiltration_query = <<-EOT
    AzureNetworkAnalytics_CL
    | where TimeGenerated > ago(1h)
    | where FlowStatus_s == "A"
    | summarize TotalBytes = sum(OutboundBytes_d) by SrcIP_s, DestIP_s, bin(TimeGenerated, 10m)
    | where TotalBytes > ${var.data_exfiltration_threshold_bytes}
    | project TimeGenerated, SrcIP_s, DestIP_s, TotalBytes, ThreatLevel = "Medium"
  EOT
  
  failed_connections_query = <<-EOT
    AzureNetworkAnalytics_CL
    | where TimeGenerated > ago(1h)
    | where FlowStatus_s == "D" and FlowType_s == "ExternalPublic"
    | summarize FailedAttempts = count() by SrcIP_s, DestIP_s, bin(TimeGenerated, 5m)
    | where FailedAttempts > ${var.failed_connection_threshold}
    | project TimeGenerated, SrcIP_s, DestIP_s, FailedAttempts, ThreatLevel = "High"
  EOT
}

# Resource Group for all network threat detection resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [tags["CreatedDate"]]
  }
}

# Data source for existing Network Watcher
data "azurerm_network_watcher" "main" {
  name                = local.network_watcher_name
  resource_group_name = var.network_watcher_resource_group_name
}

# Storage Account for NSG Flow Logs
resource "azurerm_storage_account" "flow_logs" {
  name                = "sa${replace(local.resource_prefix, "-", "")}logs"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind            = "StorageV2"
  access_tier             = var.storage_account_access_tier
  
  # Security configurations
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"
  
  # Enable blob encryption
  blob_properties {
    delete_retention_policy {
      days = var.flow_logs_retention_policy_days
    }
    container_delete_retention_policy {
      days = var.flow_logs_retention_policy_days
    }
  }
  
  # Network access rules
  network_rules {
    default_action = "Allow"  # Changed from "Deny" to avoid access issues
    bypass         = ["AzureServices"]
  }
  
  tags = local.common_tags
  
  lifecycle {
    prevent_destroy = false
    ignore_changes  = [tags["CreatedDate"]]
  }
}

# Log Analytics Workspace for security analytics
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.resource_prefix}-law"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  sku               = var.log_analytics_sku
  retention_in_days = var.log_analytics_retention_in_days
  
  tags = local.common_tags
  
  lifecycle {
    prevent_destroy = false
    ignore_changes  = [tags["CreatedDate"]]
  }
}

# Demo Network Security Group (optional, for testing)
resource "azurerm_network_security_group" "demo" {
  count               = var.create_demo_nsg ? 1 : 0
  name                = var.demo_nsg_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Sample security rules for demonstration
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = local.common_tags
  
  lifecycle {
    prevent_destroy = false
    ignore_changes  = [tags["CreatedDate"]]
  }
}

# NSG Flow Logs Configuration
resource "azurerm_network_watcher_flow_log" "demo" {
  count                     = var.create_demo_nsg ? 1 : 0
  name                      = "${local.resource_prefix}-flow-log"
  network_watcher_name      = data.azurerm_network_watcher.main.name
  resource_group_name       = data.azurerm_network_watcher.main.resource_group_name
  network_security_group_id = azurerm_network_security_group.demo[0].id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  version                   = 2
  
  retention_policy {
    enabled = true
    days    = var.flow_logs_retention_policy_days
  }
  
  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.main.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.main.location
    workspace_resource_id = azurerm_log_analytics_workspace.main.id
    interval_in_minutes   = var.flow_logs_traffic_analytics_interval
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_storage_account.flow_logs,
    azurerm_log_analytics_workspace.main
  ]
}

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "security_team" {
  name                = "${local.resource_prefix}-security-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "security"
  
  email_receiver {
    name          = "security-team"
    email_address = var.security_team_email
  }
  
  # Optional: Add webhook receiver for Logic Apps
  dynamic "webhook_receiver" {
    for_each = var.enable_logic_apps ? [1] : []
    content {
      name                    = "logic-app-webhook"
      service_uri             = azurerm_logic_app_workflow.threat_response[0].access_endpoint
      use_common_alert_schema = true
    }
  }
  
  tags = local.common_tags
}

# Alert Rule for Suspicious Port Scanning
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "port_scanning" {
  name                = "${local.resource_prefix}-port-scanning-alert"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  evaluation_frequency = "PT${var.alert_evaluation_frequency}M"
  window_duration      = "PT${var.alert_window_size}M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 1
  
  criteria {
    query                   = local.port_scanning_query
    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods              = 1
    }
  }
  
  action {
    action_groups = [azurerm_monitor_action_group.security_team.id]
  }
  
  description = "Detects suspicious port scanning activity based on denied flows"
  enabled     = true
  
  tags = local.common_tags
  
  depends_on = [azurerm_log_analytics_workspace.main]
}

# Alert Rule for Data Exfiltration
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "data_exfiltration" {
  name                = "${local.resource_prefix}-data-exfiltration-alert"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  evaluation_frequency = "PT10M"
  window_duration      = "PT${var.alert_window_size}M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 2
  
  criteria {
    query                   = local.data_exfiltration_query
    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods              = 1
    }
  }
  
  action {
    action_groups = [azurerm_monitor_action_group.security_team.id]
  }
  
  description = "Detects potential data exfiltration based on unusual data transfer volumes"
  enabled     = true
  
  tags = local.common_tags
  
  depends_on = [azurerm_log_analytics_workspace.main]
}

# Alert Rule for Failed Connection Attempts
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "failed_connections" {
  name                = "${local.resource_prefix}-failed-connections-alert"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  evaluation_frequency = "PT${var.alert_evaluation_frequency}M"
  window_duration      = "PT${var.alert_window_size}M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 1
  
  criteria {
    query                   = local.failed_connections_query
    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods              = 1
    }
  }
  
  action {
    action_groups = [azurerm_monitor_action_group.security_team.id]
  }
  
  description = "Detects excessive failed connection attempts from external IPs"
  enabled     = true
  
  tags = local.common_tags
  
  depends_on = [azurerm_log_analytics_workspace.main]
}

# Logic Apps Workflow for Automated Response
resource "azurerm_logic_app_workflow" "threat_response" {
  count               = var.enable_logic_apps ? 1 : 0
  name                = "${local.resource_prefix}-threat-response"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Basic workflow definition for threat response
  # This can be extended with more complex automation logic
  workflow_schema     = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version    = "1.0.0.0"
  
  # Workflow parameters for customization
  parameters = {
    "$connections" = jsonencode({
      defaultValue = {}
      type = "Object"
    })
  }
  
  tags = local.common_tags
  
  lifecycle {
    prevent_destroy = false
    ignore_changes  = [tags["CreatedDate"]]
  }
}

# Azure Monitor Workbook for Threat Detection Dashboard
resource "azurerm_application_insights_workbook" "threat_detection" {
  count               = var.enable_workbook_dashboard ? 1 : 0
  name                = "${local.resource_prefix}-threat-dashboard"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  display_name        = "Network Threat Detection Dashboard"
  
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Network Threat Detection Dashboard\n\nThis dashboard provides real-time monitoring of network security threats detected by Azure Network Watcher and Log Analytics."
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "AzureNetworkAnalytics_CL\n| where TimeGenerated > ago(24h)\n| where FlowStatus_s == \"D\"\n| summarize DeniedFlows = count() by bin(TimeGenerated, 1h)\n| render timechart"
          size = 0
          title = "Denied Network Flows (24h)"
          timeContext = {
            durationMs = 86400000
          }
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "AzureNetworkAnalytics_CL\n| where TimeGenerated > ago(24h)\n| where FlowStatus_s == \"D\"\n| summarize ThreatCount = count() by SrcIP_s\n| top 10 by ThreatCount desc\n| render piechart"
          size = 0
          title = "Top Threat Source IPs"
          timeContext = {
            durationMs = 86400000
          }
          queryType = 0
          resourceType = "microsoft.operationalinsights/workspaces"
        }
      }
    ]
  })
  
  tags = local.common_tags
  
  depends_on = [azurerm_log_analytics_workspace.main]
}

# Wait for Log Analytics workspace to be fully provisioned
resource "time_sleep" "wait_for_log_analytics" {
  depends_on = [azurerm_log_analytics_workspace.main]
  create_duration = "60s"
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Data source for current Azure subscription
data "azurerm_subscription" "current" {}

# Create Log Analytics solutions for enhanced capabilities
resource "azurerm_log_analytics_solution" "security_center" {
  solution_name         = "Security"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name
  
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/Security"
  }
  
  depends_on = [
    azurerm_log_analytics_workspace.main,
    time_sleep.wait_for_log_analytics
  ]
}

# Create Log Analytics solution for Azure Network Analytics
resource "azurerm_log_analytics_solution" "azure_network_analytics" {
  solution_name         = "AzureNetworkAnalytics"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name
  
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/AzureNetworkAnalytics"
  }
  
  depends_on = [
    azurerm_log_analytics_workspace.main,
    time_sleep.wait_for_log_analytics
  ]
}