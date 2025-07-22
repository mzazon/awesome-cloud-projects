# Main Terraform Configuration for Azure Cost Anomaly Detection
# This file contains the primary infrastructure resources for automated cost anomaly detection

# Data Sources
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Random Resource for Unique Naming
resource "random_string" "main" {
  length  = 6
  special = false
  upper   = false
}

# Local Values for Resource Configuration
locals {
  naming_suffix = var.naming_suffix != "" ? var.naming_suffix : random_string.main.result
  
  # Default subscription ID if not provided
  subscription_ids = length(var.monitored_subscription_ids) > 0 ? var.monitored_subscription_ids : [data.azurerm_subscription.current.subscription_id]
  
  # Common tags merged with user-defined tags
  common_tags = merge(var.tags, {
    Environment   = var.environment
    DeployedBy    = "terraform"
    CreatedDate   = timestamp()
    Solution      = "cost-anomaly-detection"
  })
  
  # Resource naming convention
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-cost-anomaly-${local.naming_suffix}"
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for Monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-cost-anomaly-${local.naming_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  
  tags = local.common_tags
}

# Application Insights for Function App Monitoring
resource "azurerm_application_insights" "main" {
  name                = "appi-cost-anomaly-${local.naming_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_days
  sampling_percentage = var.application_insights_sampling_percentage
  
  tags = local.common_tags
}

# Storage Account for Function App
resource "azurerm_storage_account" "main" {
  name                     = "stcostanomaly${local.naming_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Security settings
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"
  
  # Advanced threat protection
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }
  
  tags = local.common_tags
}

# Storage Container for Function App Data
resource "azurerm_storage_container" "function_data" {
  name                  = "function-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Cosmos DB Account for Cost Data Storage
resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-cost-anomaly-${local.naming_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  # Consistency policy
  consistency_policy {
    consistency_level       = var.cosmosdb_consistency_level
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }
  
  # Geographic location
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
  
  # Backup policy
  backup {
    type                = var.cosmosdb_backup_type
    interval_in_minutes = 240
    retention_in_hours  = 8
  }
  
  # Enable automatic failover
  automatic_failover_enabled = var.cosmosdb_enable_automatic_failover
  
  # Security settings
  public_network_access_enabled = true
  is_virtual_network_filter_enabled = false
  
  tags = local.common_tags
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "CostAnalytics"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  throughput          = var.cosmosdb_throughput
}

# Cosmos DB Container for Daily Costs
resource "azurerm_cosmosdb_sql_container" "daily_costs" {
  name                  = "DailyCosts"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.main.name
  partition_key_path    = "/date"
  partition_key_version = 1
  throughput            = var.cosmosdb_throughput
  
  # Indexing policy for optimal query performance
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
  
  # Unique key policy for data integrity
  unique_key {
    paths = ["/date", "/serviceName", "/resourceGroupName"]
  }
}

# Cosmos DB Container for Anomaly Results
resource "azurerm_cosmosdb_sql_container" "anomaly_results" {
  name                  = "AnomalyResults"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.main.name
  partition_key_path    = "/subscriptionId"
  partition_key_version = 1
  throughput            = var.cosmosdb_throughput
  
  # Indexing policy for anomaly queries
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    included_path {
      path = "/severity/?"
    }
    
    included_path {
      path = "/anomalyType/?"
    }
  }
  
  # Time-to-live for automatic cleanup of old anomalies
  default_ttl = 2592000  # 30 days
}

# Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = "plan-cost-anomaly-${local.naming_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Function App for Cost Anomaly Detection
resource "azurerm_linux_function_app" "main" {
  name                = "func-cost-anomaly-${local.naming_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id            = azurerm_service_plan.main.id
  
  # Function App configuration
  site_config {
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # CORS configuration
    cors {
      allowed_origins = var.allowed_cors_origins
    }
    
    # Security settings
    ftps_state = "Disabled"
    
    # Application settings
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }
  
  # App settings for cost management
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "python"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "COSMOS_ENDPOINT"              = azurerm_cosmosdb_account.main.endpoint
    "COSMOS_CONNECTION"            = azurerm_cosmosdb_account.main.connection_strings[0]
    "SUBSCRIPTION_ID"              = data.azurerm_subscription.current.subscription_id
    "ANOMALY_THRESHOLD"            = tostring(var.anomaly_threshold)
    "LOOKBACK_DAYS"                = tostring(var.lookback_days)
    "MONITORED_SUBSCRIPTIONS"      = jsonencode(local.subscription_ids)
    "NOTIFICATION_EMAIL"           = var.notification_email
    "TEAMS_WEBHOOK_URL"            = var.teams_webhook_url
    "FUNCTION_TIMEOUT_MINUTES"     = tostring(var.function_timeout_minutes)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
  }
  
  # Managed identity configuration
  identity {
    type = var.enable_managed_identity ? "SystemAssigned" : null
  }
  
  # Security settings
  https_only = var.enable_https_only
  
  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
    ]
  }
}

# Role Assignment for Function App to Access Cost Management
resource "azurerm_role_assignment" "cost_management_reader" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
  role_definition_name = "Cost Management Reader"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment for Function App to Access Cosmos DB
resource "azurerm_cosmosdb_sql_role_assignment" "cosmos_contributor" {
  count               = var.enable_managed_identity ? 1 : 0
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.DocumentDB/databaseAccounts/${azurerm_cosmosdb_account.main.name}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_linux_function_app.main.identity[0].principal_id
  scope               = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.DocumentDB/databaseAccounts/${azurerm_cosmosdb_account.main.name}"
}

# Logic App for Advanced Workflow Automation (Optional)
resource "azurerm_logic_app_workflow" "main" {
  count               = var.logic_app_enabled ? 1 : 0
  name                = "logic-cost-alerts-${local.naming_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Logic App Trigger for Cost Anomaly Detection
resource "azurerm_logic_app_trigger_recurrence" "anomaly_check" {
  count        = var.logic_app_enabled ? 1 : 0
  name         = "anomaly-check-trigger"
  logic_app_id = azurerm_logic_app_workflow.main[0].id
  frequency    = var.logic_app_frequency
  interval     = var.logic_app_interval
  
  depends_on = [azurerm_logic_app_workflow.main]
}

# Diagnostic Settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-func-cost-anomaly-${local.naming_suffix}"
  target_resource_id = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "FunctionAppLogs"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  metric {
    category = "AllMetrics"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Diagnostic Settings for Cosmos DB
resource "azurerm_monitor_diagnostic_setting" "cosmos_db" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-cosmos-cost-anomaly-${local.naming_suffix}"
  target_resource_id = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "DataPlaneRequests"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "QueryRuntimeStatistics"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  metric {
    category = "Requests"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "diag-storage-cost-anomaly-${local.naming_suffix}"
  target_resource_id = "${azurerm_storage_account.main.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "StorageRead"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "StorageWrite"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  metric {
    category = "Transaction"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Alert Rule for High Cost Anomalies
resource "azurerm_monitor_metric_alert" "high_cost_anomaly" {
  name                = "alert-high-cost-anomaly-${local.naming_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.main.id]
  description         = "Alert when function app detects high-severity cost anomalies"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 10
    
    dimension {
      name     = "FunctionName"
      operator = "Include"
      values   = ["AnomalyDetector"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
}

# Action Group for Notifications
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-cost-anomaly-${local.naming_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "costanomaly"
  
  dynamic "email_receiver" {
    for_each = var.notification_email != "" ? [1] : []
    content {
      name          = "admin-email"
      email_address = var.notification_email
    }
  }
  
  dynamic "webhook_receiver" {
    for_each = var.teams_webhook_url != "" ? [1] : []
    content {
      name        = "teams-webhook"
      service_uri = var.teams_webhook_url
    }
  }
  
  tags = local.common_tags
}

# Budget for Cost Monitoring
resource "azurerm_consumption_budget_subscription" "main" {
  name            = "budget-cost-anomaly-monitoring-${local.naming_suffix}"
  subscription_id = data.azurerm_subscription.current.subscription_id
  
  amount     = 100
  time_grain = "Monthly"
  
  time_period {
    start_date = "2024-01-01T00:00:00Z"
    end_date   = "2025-12-31T23:59:59Z"
  }
  
  filter {
    dimension {
      name = "ResourceGroupName"
      values = [azurerm_resource_group.main.name]
    }
  }
  
  notification {
    enabled   = true
    threshold = 80
    operator  = "GreaterThan"
    
    contact_emails = var.notification_email != "" ? [var.notification_email] : []
  }
  
  notification {
    enabled   = true
    threshold = 100
    operator  = "GreaterThan"
    
    contact_emails = var.notification_email != "" ? [var.notification_email] : []
  }
}