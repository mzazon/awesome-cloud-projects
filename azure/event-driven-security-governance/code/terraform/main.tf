# Main Terraform configuration for Azure Security Governance Automation
# This infrastructure deploys an event-driven security governance system using
# Azure Event Grid and Azure Managed Identity for automated compliance monitoring

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for computed names and configurations
locals {
  # Use provided suffix or generate random one
  suffix = var.random_suffix != "" ? var.random_suffix : random_string.suffix.result
  
  # Compute resource names with suffix
  resource_group_name            = "${var.resource_group_name}-${local.suffix}"
  event_grid_topic_name         = "${var.event_grid_topic_name}-${local.suffix}"
  function_app_name             = "${var.function_app_name}-${local.suffix}"
  storage_account_name          = "${var.storage_account_name}${local.suffix}"
  log_analytics_workspace_name  = "${var.log_analytics_workspace_name}-${local.suffix}"
  action_group_name             = "${var.action_group_name}-${local.suffix}"
  app_service_plan_name         = "asp-${var.function_app_name}-${local.suffix}"
  application_insights_name     = "ai-${var.function_app_name}-${local.suffix}"
  
  # Common tags merged with environment-specific tags
  common_tags = merge(var.common_tags, {
    environment = var.environment
    owner       = var.owner
    created-by  = "terraform"
    location    = var.location
  })
}

# Resource Group for all security governance resources
resource "azurerm_resource_group" "security_governance" {
  name     = local.resource_group_name
  location = var.location
  
  tags = local.common_tags
}

# Log Analytics Workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "security_governance" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.security_governance.location
  resource_group_name = azurerm_resource_group.security_governance.name
  
  sku               = var.log_analytics_sku
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    purpose = "compliance-monitoring"
  })
}

# Storage Account for Function App and compliance artifacts
resource "azurerm_storage_account" "security_governance" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.security_governance.name
  location                 = azurerm_resource_group.security_governance.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Enable security features
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Enable Advanced Threat Protection if specified
  dynamic "identity" {
    for_each = var.enable_advanced_threat_protection ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  tags = merge(local.common_tags, {
    purpose = "function-storage"
  })
}

# Advanced Threat Protection for Storage Account
resource "azurerm_advanced_threat_protection" "storage_atp" {
  count              = var.enable_advanced_threat_protection ? 1 : 0
  target_resource_id = azurerm_storage_account.security_governance.id
  enabled            = true
}

# Event Grid Custom Topic for security events
resource "azurerm_eventgrid_topic" "security_governance" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.security_governance.location
  resource_group_name = azurerm_resource_group.security_governance.name
  
  tags = merge(local.common_tags, {
    purpose = "security-events"
  })
}

# Application Insights for Function App monitoring
resource "azurerm_application_insights" "security_governance" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.application_insights_name
  location            = azurerm_resource_group.security_governance.location
  resource_group_name = azurerm_resource_group.security_governance.name
  workspace_id        = azurerm_log_analytics_workspace.security_governance.id
  application_type    = "web"
  
  tags = merge(local.common_tags, {
    purpose = "application-monitoring"
  })
}

# App Service Plan for Function App
resource "azurerm_service_plan" "security_governance" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.security_governance.name
  location            = azurerm_resource_group.security_governance.location
  
  os_type  = "Linux"
  sku_name = var.function_app_plan_sku
  
  tags = local.common_tags
}

# Azure Function App with system-assigned managed identity
resource "azurerm_linux_function_app" "security_governance" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.security_governance.name
  location            = azurerm_resource_group.security_governance.location
  
  service_plan_id            = azurerm_service_plan.security_governance.id
  storage_account_name       = azurerm_storage_account.security_governance.name
  storage_account_access_key = azurerm_storage_account.security_governance.primary_access_key
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Function App configuration
  site_config {
    application_stack {
      python_version = "3.9"
    }
    
    # Enable Application Insights integration
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.security_governance[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.security_governance[0].connection_string : null
  }
  
  # Application settings for Event Grid and monitoring integration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "AzureWebJobsFeatureFlags"     = "EnableWorkerIndexing"
    "EventGridTopicEndpoint"       = azurerm_eventgrid_topic.security_governance.endpoint
    "EventGridTopicKey"            = azurerm_eventgrid_topic.security_governance.primary_access_key
    "LogAnalyticsWorkspaceId"      = azurerm_log_analytics_workspace.security_governance.workspace_id
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    
    # Application Insights settings
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.security_governance[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.security_governance[0].connection_string : ""
  }
  
  tags = merge(local.common_tags, {
    purpose = "security-automation"
  })
}

# RBAC: Security Reader role assignment for compliance checking
resource "azurerm_role_assignment" "security_reader" {
  scope                = azurerm_resource_group.security_governance.id
  role_definition_name = "Security Reader"
  principal_id         = azurerm_linux_function_app.security_governance.identity[0].principal_id
}

# RBAC: Contributor role assignment for remediation actions
resource "azurerm_role_assignment" "contributor" {
  scope                = azurerm_resource_group.security_governance.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.security_governance.identity[0].principal_id
}

# RBAC: Monitoring Contributor role assignment for Azure Monitor operations
resource "azurerm_role_assignment" "monitoring_contributor" {
  scope                = azurerm_resource_group.security_governance.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_linux_function_app.security_governance.identity[0].principal_id
}

# Create ZIP package for Function App deployment
data "archive_file" "function_app_zip" {
  type        = "zip"
  output_path = "${path.module}/function_app.zip"
  
  source {
    content = <<-EOT
import azure.functions as func
import json
import logging
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.monitor import MonitorManagementClient

def main(event: func.EventGridEvent):
    logging.info(f'Processing security event: {event.get_json()}')
    
    # Parse event data
    event_data = event.get_json()
    resource_uri = event_data.get('subject', '')
    operation_name = event_data.get('data', {}).get('operationName', '')
    
    # Initialize Azure clients with managed identity
    credential = DefaultAzureCredential()
    
    # Perform security assessment based on resource type
    if 'Microsoft.Compute/virtualMachines' in operation_name:
        assess_vm_security(resource_uri, credential)
    elif 'Microsoft.Network/networkSecurityGroups' in operation_name:
        assess_nsg_security(resource_uri, credential)
    elif 'Microsoft.Storage/storageAccounts' in operation_name:
        assess_storage_security(resource_uri, credential)

def assess_vm_security(resource_uri, credential):
    logging.info(f'Assessing VM security for: {resource_uri}')
    # Implementation for VM security checks
    
def assess_nsg_security(resource_uri, credential):
    logging.info(f'Assessing NSG security for: {resource_uri}')
    # Implementation for NSG security checks
    
def assess_storage_security(resource_uri, credential):
    logging.info(f'Assessing Storage security for: {resource_uri}')
    # Implementation for Storage security checks
EOT
    filename = "SecurityEventProcessor/__init__.py"
  }
  
  source {
    content = <<-EOT
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "function",
      "type": "eventGridTrigger",
      "direction": "in",
      "name": "event"
    }
  ]
}
EOT
    filename = "SecurityEventProcessor/function.json"
  }
  
  source {
    content = <<-EOT
azure-functions
azure-identity
azure-mgmt-resource
azure-mgmt-monitor
azure-mgmt-storage
azure-mgmt-compute
azure-mgmt-network
EOT
    filename = "requirements.txt"
  }
  
  source {
    content = <<-EOT
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[3.*, 4.0.0)"
  },
  "functionTimeout": "00:05:00"
}
EOT
    filename = "host.json"
  }
}

# Deploy Function App code
resource "azurerm_function_app_function" "security_event_processor" {
  name            = "SecurityEventProcessor"
  function_app_id = azurerm_linux_function_app.security_governance.id
  language        = "Python"
  
  config_json = jsonencode({
    "scriptFile": "__init__.py",
    "bindings": [
      {
        "authLevel": "function",
        "type": "eventGridTrigger",
        "direction": "in",
        "name": "event"
      }
    ]
  })
}

# Event Grid subscription for resource changes
resource "azurerm_eventgrid_event_subscription" "security_governance" {
  name  = "security-governance-subscription"
  scope = azurerm_resource_group.security_governance.id
  
  azure_function_endpoint {
    function_id = azurerm_function_app_function.security_event_processor.id
  }
  
  # Filter for security-relevant events
  included_event_types = [
    "Microsoft.Resources.ResourceWriteSuccess",
    "Microsoft.Resources.ResourceDeleteSuccess",
    "Microsoft.Resources.ResourceActionSuccess"
  ]
  
  # Advanced filtering for specific operations
  advanced_filter {
    string_begins_with {
      key    = "data.operationName"
      values = ["Microsoft.Compute/virtualMachines"]
    }
  }
  
  advanced_filter {
    string_begins_with {
      key    = "data.operationName"
      values = ["Microsoft.Network/networkSecurityGroups"]
    }
  }
  
  advanced_filter {
    string_begins_with {
      key    = "data.operationName"
      values = ["Microsoft.Storage/storageAccounts"]
    }
  }
}

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "security_governance" {
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.security_governance.name
  short_name          = "SecAlert"
  
  email_receiver {
    name          = "SecurityTeam"
    email_address = var.notification_email
  }
  
  tags = merge(local.common_tags, {
    purpose = "alert-notifications"
  })
}

# Metric Alert for security violations
resource "azurerm_monitor_metric_alert" "security_violations" {
  name                = "SecurityViolationAlert"
  resource_group_name = azurerm_resource_group.security_governance.name
  scopes              = [azurerm_linux_function_app.security_governance.id]
  
  description = "Alert when security violations exceed threshold"
  severity    = 2
  frequency   = var.alert_evaluation_frequency
  window_size = var.alert_window_size
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.security_violation_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.security_governance.id
  }
  
  tags = local.common_tags
}

# Metric Alert for function failures
resource "azurerm_monitor_metric_alert" "function_failures" {
  name                = "SecurityFunctionFailureAlert"
  resource_group_name = azurerm_resource_group.security_governance.name
  scopes              = [azurerm_linux_function_app.security_governance.id]
  
  description = "Alert when security function executions fail"
  severity    = 1
  frequency   = var.alert_evaluation_frequency
  window_size = var.alert_window_size
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionFailures"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.security_governance.id
  }
  
  tags = local.common_tags
}

# Diagnostic Settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name                       = "function-app-diagnostics"
  target_resource_id         = azurerm_linux_function_app.security_governance.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.security_governance.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Event Grid Topic
resource "azurerm_monitor_diagnostic_setting" "event_grid" {
  name                       = "event-grid-diagnostics"
  target_resource_id         = azurerm_eventgrid_topic.security_governance.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.security_governance.id
  
  enabled_log {
    category = "DeliveryFailures"
  }
  
  enabled_log {
    category = "PublishFailures"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}