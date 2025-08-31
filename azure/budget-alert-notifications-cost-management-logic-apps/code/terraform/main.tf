# Azure Budget Alert Notifications with Cost Management and Logic Apps
# This configuration creates a complete budget monitoring solution with automated notifications

# Get current client configuration for resource naming and permissions
data "azurerm_client_config" "current" {}

# Get current subscription for budget creation
data "azurerm_subscription" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent resource naming and tagging
locals {
  # Generate unique suffix if not provided
  suffix = var.name_suffix != "" ? var.name_suffix : random_string.suffix.result
  
  # Consistent resource naming convention
  resource_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with unique suffix
  resource_group_name    = "rg-${local.resource_prefix}-${local.suffix}"
  storage_account_name   = "st${replace(local.resource_prefix, "-", "")}${local.suffix}"
  logic_app_name         = "la-${local.resource_prefix}-${local.suffix}"
  action_group_name      = "ag-${local.resource_prefix}-${local.suffix}"
  budget_name           = "budget-${local.resource_prefix}-${local.suffix}"
  app_service_plan_name = "asp-${local.resource_prefix}-${local.suffix}"
  
  # Combined tags for all resources
  common_tags = merge(
    var.common_tags,
    var.additional_tags,
    {
      Environment   = var.environment
      Project      = var.project_name
      ManagedBy    = "terraform"
      Purpose      = "budget-monitoring"
      CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
      ResourceType = "budget-alert-system"
    }
  )
}

# Resource Group - Container for all budget monitoring resources
resource "azurerm_resource_group" "budget_alerts" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Storage Account - Required for Logic App runtime and state management
resource "azurerm_storage_account" "logic_app_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.budget_alerts.name
  location                = azurerm_resource_group.budget_alerts.location
  account_tier            = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind            = "StorageV2"
  
  # Security configurations
  https_traffic_only_enabled       = var.enable_https_only
  min_tls_version                  = var.min_tls_version
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  
  # Network access rules for enhanced security
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  # Blob properties for lifecycle management
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = false
    
    # Enable soft delete for data protection
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = merge(local.common_tags, {
    Component = "storage"
    Purpose   = "logic-app-runtime"
  })
}

# App Service Plan - Required for Logic App Standard hosting
resource "azurerm_service_plan" "logic_app_plan" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.budget_alerts.name
  location            = azurerm_resource_group.budget_alerts.location
  os_type             = "Windows"
  sku_name            = var.logic_app_sku_name
  
  tags = merge(local.common_tags, {
    Component = "compute"
    Purpose   = "logic-app-hosting"
  })
}

# Logic App - Serverless workflow for processing budget alerts
resource "azurerm_logic_app_standard" "budget_processor" {
  name                       = local.logic_app_name
  resource_group_name        = azurerm_resource_group.budget_alerts.name
  location                  = azurerm_resource_group.budget_alerts.location
  app_service_plan_id       = azurerm_service_plan.logic_app_plan.id
  storage_account_name      = azurerm_storage_account.logic_app_storage.name
  storage_account_access_key = azurerm_storage_account.logic_app_storage.primary_access_key
  
  # Application settings for Logic App configuration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~18"
    "FUNCTIONS_EXTENSION_VERSION"    = "~4"
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.logic_app_storage.primary_connection_string
    "WEBSITE_CONTENTSHARE"           = "${local.logic_app_name}-content"
    "AzureWebJobsStorage"           = azurerm_storage_account.logic_app_storage.primary_connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.budget_monitoring.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.budget_monitoring.connection_string
  }
  
  # Site configuration for enhanced performance and security
  site_config {
    always_on                = true
    use_32_bit_worker        = false
    dotnet_framework_version = "v6.0"
    
    # CORS configuration for web-based management
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
  }
  
  # Enable HTTPS only for security
  https_only = true
  
  tags = merge(local.common_tags, {
    Component = "automation"
    Purpose   = "budget-alert-processing"
  })
  
  depends_on = [
    azurerm_storage_account.logic_app_storage,
    azurerm_service_plan.logic_app_plan
  ]
}

# Application Insights - Monitoring and diagnostics for Logic App
resource "azurerm_application_insights" "budget_monitoring" {
  name                = "ai-${local.resource_prefix}-${local.suffix}"
  resource_group_name = azurerm_resource_group.budget_alerts.name
  location           = azurerm_resource_group.budget_alerts.location
  application_type   = "web"
  
  # Retention configuration
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Component = "monitoring"
    Purpose   = "logic-app-insights"
  })
}

# Action Group - Defines notification channels for budget alerts
resource "azurerm_monitor_action_group" "budget_alerts" {
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.budget_alerts.name
  short_name          = "BudgetAlert"
  
  # Logic App receiver for automated processing
  logic_app_receiver {
    name                    = "BudgetLogicApp"
    resource_id            = azurerm_logic_app_standard.budget_processor.id
    callback_url           = "https://${azurerm_logic_app_standard.budget_processor.default_hostname}/api/budget-alert-webhook"
    use_common_alert_schema = true
  }
  
  # Email receivers for direct notifications (if configured)
  dynamic "email_receiver" {
    for_each = var.notification_emails
    content {
      name          = "EmailReceiver-${email_receiver.key + 1}"
      email_address = email_receiver.value
    }
  }
  
  tags = merge(local.common_tags, {
    Component = "monitoring"
    Purpose   = "alert-notification"
  })
  
  depends_on = [azurerm_logic_app_standard.budget_processor]
}

# Consumption Budget - Monitors spending and triggers alerts
resource "azurerm_consumption_budget_subscription" "monthly_budget" {
  name            = local.budget_name
  subscription_id = data.azurerm_subscription.current.id
  
  # Budget amount and time configuration
  amount     = var.budget_amount
  time_grain = "Monthly"
  
  # Budget period configuration
  time_period {
    start_date = "${var.budget_start_date}T00:00:00Z"
    end_date   = "${var.budget_end_date}T00:00:00Z"
  }
  
  # Filter to include all costs (can be customized for specific resource groups)
  filter {
    # Monitor all subscription costs
    dimension {
      name   = "ResourceGroupName"
      values = ["*"]
    }
  }
  
  # Dynamic notification configuration based on alert thresholds
  dynamic "notification" {
    for_each = var.alert_thresholds
    content {
      enabled        = notification.value.enabled
      threshold      = notification.value.threshold
      operator       = notification.value.operator
      threshold_type = startswith(notification.key, "actual") ? "Actual" : "Forecasted"
      
      # Contact groups for automated processing
      contact_groups = [azurerm_monitor_action_group.budget_alerts.id]
      
      # Contact emails for direct notifications
      contact_emails = var.notification_emails
    }
  }
  
  depends_on = [azurerm_monitor_action_group.budget_alerts]
}

# Diagnostic Settings for Logic App - Enable comprehensive logging
resource "azurerm_monitor_diagnostic_setting" "logic_app_diagnostics" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                      = "diag-${local.logic_app_name}"
  target_resource_id        = azurerm_logic_app_standard.budget_processor.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.budget_monitoring[0].id
  
  # Enable all available log categories
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  
  # Enable all available metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  depends_on = [
    azurerm_logic_app_standard.budget_processor,
    azurerm_log_analytics_workspace.budget_monitoring
  ]
}

# Log Analytics Workspace - Centralized logging for monitoring and troubleshooting
resource "azurerm_log_analytics_workspace" "budget_monitoring" {
  count               = var.enable_diagnostic_settings ? 1 : 0
  name                = "law-${local.resource_prefix}-${local.suffix}"
  resource_group_name = azurerm_resource_group.budget_alerts.name
  location           = azurerm_resource_group.budget_alerts.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Component = "monitoring"
    Purpose   = "centralized-logging"
  })
}

# Diagnostic Settings for Storage Account - Monitor storage operations
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                      = "diag-${local.storage_account_name}"
  target_resource_id        = azurerm_storage_account.logic_app_storage.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.budget_monitoring[0].id
  
  # Enable storage metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  depends_on = [
    azurerm_storage_account.logic_app_storage,
    azurerm_log_analytics_workspace.budget_monitoring
  ]
}