# Main Terraform Configuration
# Autonomous Database Scaling with Azure SQL Database Hyperscale and Logic Apps
# This file contains the core infrastructure for the autonomous scaling solution

# Data Sources for Current Deployment Context
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Generate secure password for SQL Server if not provided
resource "random_password" "sql_admin_password" {
  count   = var.sql_server_admin_password == null ? 1 : 0
  length  = 16
  special = true
  
  # Ensure password meets Azure SQL requirements
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

# Local values for computed configurations
locals {
  # Generate unique resource names with project and environment context
  resource_prefix = "${var.project_name}-${var.environment}"
  resource_suffix = random_string.suffix.result
  
  # Resource names with uniqueness guarantee
  resource_group_name    = var.resource_group_name != null ? var.resource_group_name : "rg-${local.resource_prefix}-${local.resource_suffix}"
  sql_server_name       = "sql-${local.resource_prefix}-${local.resource_suffix}"
  key_vault_name        = "kv-${local.resource_prefix}-${local.resource_suffix}"
  logic_app_name        = "logic-${local.resource_prefix}-${local.resource_suffix}"
  log_analytics_name    = "la-${local.resource_prefix}-${local.resource_suffix}"
  action_group_name     = "ag-${local.resource_prefix}-${local.resource_suffix}"
  storage_account_name  = "st${replace(local.resource_prefix, "-", "")}${local.resource_suffix}"
  
  # SQL Server configuration
  sql_admin_password = var.sql_server_admin_password != null ? var.sql_server_admin_password : random_password.sql_admin_password[0].result
  
  # Extract vCore count from initial SKU for scaling calculations
  initial_vcores = tonumber(regex("HS_Gen5_([0-9]+)", var.sql_database_initial_sku)[0])
  
  # Common tags merged with user-provided tags
  common_tags = merge(var.common_tags, {
    Environment     = var.environment
    Project        = var.project_name
    ResourceGroup  = local.resource_group_name
    DeployedAt     = timestamp()
    ManagedBy      = "Terraform"
  })
}

# Resource Group - Container for all solution resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace - Central logging and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.common_tags, {
    Purpose = "Monitoring and logging for autonomous scaling solution"
  })
}

# Storage Account - Required for Logic Apps and diagnostics
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_account_replication_type
  
  # Security configurations
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  blob_properties {
    # Enable versioning and soft delete for compliance
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Storage for Logic Apps and diagnostic data"
  })
}

# Key Vault - Secure storage for credentials and configuration
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  
  # Security configurations
  enable_rbac_authorization       = var.enable_key_vault_rbac
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  soft_delete_retention_days      = 7
  purge_protection_enabled        = false  # Set to true for production
  
  # Network access configuration
  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"  # Restrict in production environments
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Secure credential storage for scaling automation"
  })
}

# Key Vault Secrets - Store SQL credentials securely
resource "azurerm_key_vault_secret" "sql_admin_username" {
  name         = "sql-admin-username"
  value        = var.sql_server_admin_username
  key_vault_id = azurerm_key_vault.main.id
  
  tags = {
    Purpose = "SQL Server administrator username"
  }
  
  depends_on = [azurerm_role_assignment.current_user_kv_admin]
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = local.sql_admin_password
  key_vault_id = azurerm_key_vault.main.id
  
  tags = {
    Purpose = "SQL Server administrator password"
  }
  
  depends_on = [azurerm_role_assignment.current_user_kv_admin]
}

# SQL Server - Hyperscale database host
resource "azurerm_mssql_server" "main" {
  name                = local.sql_server_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  version             = "12.0"
  
  # Authentication configuration
  administrator_login          = var.sql_server_admin_username
  administrator_login_password = local.sql_admin_password
  
  # Security configurations
  public_network_access_enabled = var.sql_server_public_access_enabled
  minimum_tls_version           = "1.2"
  
  # Azure AD authentication configuration
  azuread_administrator {
    login_username = data.azuread_client_config.current.object_id
    object_id      = data.azuread_client_config.current.object_id
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Hyperscale database server for autonomous scaling"
  })
}

# SQL Server Firewall Rules - Allow Azure services and specified IP ranges
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Additional firewall rules for specified IP ranges
resource "azurerm_mssql_firewall_rule" "custom_ranges" {
  for_each = {
    for idx, rule in var.allowed_ip_ranges : idx => rule
  }
  
  name             = each.value.name
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = each.value.start_ip
  end_ip_address   = each.value.end_ip
}

# SQL Database - Hyperscale database with autonomous scaling capabilities
resource "azurerm_mssql_database" "main" {
  name           = var.sql_database_name
  server_id      = azurerm_mssql_server.main.id
  sku_name       = var.sql_database_initial_sku
  max_size_gb    = var.sql_database_max_size_gb
  zone_redundant = var.enable_zone_redundancy
  
  # Backup configuration
  short_term_retention_policy {
    retention_days = var.backup_retention_days
  }
  
  # Threat detection configuration
  dynamic "threat_detection_policy" {
    for_each = var.enable_threat_detection ? [1] : []
    content {
      state                      = "Enabled"
      email_account_admins       = "Enabled"
      email_addresses            = var.alert_email_recipients
      retention_days             = 30
      storage_account_access_key = azurerm_storage_account.main.primary_access_key
      storage_endpoint           = azurerm_storage_account.main.primary_blob_endpoint
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose    = "Hyperscale database with autonomous scaling"
    InitialSKU = var.sql_database_initial_sku
    MaxVCores  = var.max_vcores
    MinVCores  = var.min_vcores
  })
}

# Extended Auditing Policy for SQL Database
resource "azurerm_mssql_database_extended_auditing_policy" "main" {
  database_id            = azurerm_mssql_database.main.id
  storage_endpoint       = azurerm_storage_account.main.primary_blob_endpoint
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  retention_in_days      = 30
  
  depends_on = [azurerm_storage_account.main]
}

# Application Insights - Enhanced monitoring for Logic Apps
resource "azurerm_application_insights" "main" {
  name                = "ai-${local.resource_prefix}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  tags = merge(local.common_tags, {
    Purpose = "Application monitoring for scaling automation"
  })
}

# Action Group - Notification endpoint for scaling alerts
resource "azurerm_monitor_action_group" "scaling_alerts" {
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ScaleAlert"
  
  # Email notifications for scaling events
  dynamic "email_receiver" {
    for_each = var.alert_email_recipients
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
  
  # Logic App webhook receiver for scaling automation
  webhook_receiver {
    name                    = "logic-app-scaling"
    service_uri             = azurerm_logic_app_trigger_http_request.scaling_trigger.callback_url
    use_common_alert_schema = true
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Alert notifications for database scaling events"
  })
}

# CPU Scale-Up Alert Rule
resource "azurerm_monitor_metric_alert" "cpu_scale_up" {
  name                = "cpu-scale-up-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_mssql_database.main.id]
  description         = "Trigger scale-up when CPU exceeds ${var.cpu_scale_up_threshold}% for ${var.scale_up_evaluation_window_minutes} minutes"
  
  # Alert configuration
  severity    = 2
  frequency   = "PT1M"  # Check every minute
  window_size = "PT${var.scale_up_evaluation_window_minutes}M"
  
  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_scale_up_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.scaling_alerts.id
    webhook_properties = {
      alertType = "CPU-Scale-Up-Alert"
      scaleDirection = "up"
      threshold = var.cpu_scale_up_threshold
      evaluationWindow = var.scale_up_evaluation_window_minutes
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "CPU-based scale-up trigger"
    Threshold = "${var.cpu_scale_up_threshold}%"
  })
}

# CPU Scale-Down Alert Rule
resource "azurerm_monitor_metric_alert" "cpu_scale_down" {
  name                = "cpu-scale-down-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_mssql_database.main.id]
  description         = "Trigger scale-down when CPU below ${var.cpu_scale_down_threshold}% for ${var.scale_down_evaluation_window_minutes} minutes"
  
  # Alert configuration with longer evaluation to prevent flapping
  severity    = 3
  frequency   = "PT5M"  # Check every 5 minutes
  window_size = "PT${var.scale_down_evaluation_window_minutes}M"
  
  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.cpu_scale_down_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.scaling_alerts.id
    webhook_properties = {
      alertType = "CPU-Scale-Down-Alert"
      scaleDirection = "down"
      threshold = var.cpu_scale_down_threshold
      evaluationWindow = var.scale_down_evaluation_window_minutes
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "CPU-based scale-down trigger"
    Threshold = "${var.cpu_scale_down_threshold}%"
  })
}

# Logic App - Autonomous scaling orchestration workflow
resource "azurerm_logic_app_workflow" "scaling" {
  name                = local.logic_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Complete workflow definition with intelligent scaling logic
  workflow_schema   = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"
  
  parameters = {
    resourceGroup = azurerm_resource_group.main.name
    serverName    = azurerm_mssql_server.main.name
    databaseName  = azurerm_mssql_database.main.name
    maxVCores     = var.max_vcores
    minVCores     = var.min_vcores
    scalingStepSize = var.scaling_step_size
    subscriptionId = data.azurerm_client_config.current.subscription_id
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Autonomous database scaling orchestration"
    MaxVCores = var.max_vcores
    MinVCores = var.min_vcores
  })
}

# Logic App Trigger - HTTP endpoint for scaling alerts
resource "azurerm_logic_app_trigger_http_request" "scaling_trigger" {
  name         = "scaling-trigger"
  logic_app_id = azurerm_logic_app_workflow.scaling.id
  
  schema = jsonencode({
    type = "object"
    properties = {
      alertType = {
        type = "string"
        description = "Type of scaling alert (CPU-Scale-Up-Alert or CPU-Scale-Down-Alert)"
      }
      resourceId = {
        type = "string"
        description = "Resource ID of the database triggering the alert"
      }
      metricValue = {
        type = "number"
        description = "Current metric value that triggered the alert"
      }
      threshold = {
        type = "number"
        description = "Threshold value that was crossed"
      }
      scaleDirection = {
        type = "string"
        description = "Direction of scaling (up or down)"
      }
      evaluationWindow = {
        type = "number"
        description = "Evaluation window in minutes"
      }
    }
    required = ["alertType", "resourceId", "metricValue", "scaleDirection"]
  })
}

# Logic App Actions for Database Scaling Operations

# Action to get current database configuration
resource "azurerm_logic_app_action_http" "get_database_config" {
  name         = "get-database-config"
  logic_app_id = azurerm_logic_app_workflow.scaling.id
  method       = "GET"
  uri          = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Sql/servers/${azurerm_mssql_server.main.name}/databases/${azurerm_mssql_database.main.name}"
  
  headers = {
    "Content-Type" = "application/json"
  }
  
  queries = {
    "api-version" = "2021-11-01"
  }
  
  depends_on = [azurerm_logic_app_trigger_http_request.scaling_trigger]
}

# Action to calculate new capacity based on scaling direction
resource "azurerm_logic_app_action_custom" "calculate_capacity" {
  name         = "calculate-capacity"
  logic_app_id = azurerm_logic_app_workflow.scaling.id
  
  body = jsonencode({
    type = "Compose"
    inputs = {
      scaleUp = {
        newCapacity = "@min(add(int(body('get-database-config')?['properties']?['currentServiceObjectiveName']?[8:]), ${var.scaling_step_size}), ${var.max_vcores})"
      }
      scaleDown = {
        newCapacity = "@max(sub(int(body('get-database-config')?['properties']?['currentServiceObjectiveName']?[8:]), ${var.scaling_step_size}), ${var.min_vcores})"
      }
      currentVCores = "@int(body('get-database-config')?['properties']?['currentServiceObjectiveName']?[8:])"
    }
  })
  
  depends_on = [azurerm_logic_app_action_http.get_database_config]
}

# Action to scale up the database
resource "azurerm_logic_app_action_http" "scale_up_database" {
  name         = "scale-up-database"
  logic_app_id = azurerm_logic_app_workflow.scaling.id
  method       = "PATCH"
  uri          = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Sql/servers/${azurerm_mssql_server.main.name}/databases/${azurerm_mssql_database.main.name}"
  
  headers = {
    "Content-Type" = "application/json"
  }
  
  queries = {
    "api-version" = "2021-11-01"
  }
  
  body = jsonencode({
    properties = {
      requestedServiceObjectiveName = "@concat('HS_Gen5_', string(outputs('calculate-capacity')?['scaleUp']?['newCapacity']))"
    }
  })
  
  depends_on = [azurerm_logic_app_action_custom.calculate_capacity]
}

# Action to scale down the database
resource "azurerm_logic_app_action_http" "scale_down_database" {
  name         = "scale-down-database"
  logic_app_id = azurerm_logic_app_workflow.scaling.id
  method       = "PATCH"
  uri          = "https://management.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Sql/servers/${azurerm_mssql_server.main.name}/databases/${azurerm_mssql_database.main.name}"
  
  headers = {
    "Content-Type" = "application/json"
  }
  
  queries = {
    "api-version" = "2021-11-01"
  }
  
  body = jsonencode({
    properties = {
      requestedServiceObjectiveName = "@concat('HS_Gen5_', string(outputs('calculate-capacity')?['scaleDown']?['newCapacity']))"
    }
  })
  
  depends_on = [azurerm_logic_app_action_custom.calculate_capacity]
}

# Action to log scaling operation
resource "azurerm_logic_app_action_http" "log_scaling_operation" {
  name         = "log-scaling-operation"
  logic_app_id = azurerm_logic_app_workflow.scaling.id
  method       = "POST"
  uri          = "https://${azurerm_log_analytics_workspace.main.name}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
  
  headers = {
    "Content-Type" = "application/json"
    "Log-Type"     = "DatabaseScaling"
  }
  
  body = jsonencode({
    timestamp = "@utcnow()"
    alertType = "@triggerBody()?['alertType']"
    metricValue = "@triggerBody()?['metricValue']"
    threshold = "@triggerBody()?['threshold']"
    scaleDirection = "@triggerBody()?['scaleDirection']"
    currentVCores = "@outputs('calculate-capacity')?['currentVCores']"
    newVCores = "@if(equals(triggerBody()?['scaleDirection'], 'up'), outputs('calculate-capacity')?['scaleUp']?['newCapacity'], outputs('calculate-capacity')?['scaleDown']?['newCapacity'])"
    resourceId = "@triggerBody()?['resourceId']"
    evaluationWindow = "@triggerBody()?['evaluationWindow']"
  })
  
  depends_on = [
    azurerm_logic_app_action_http.scale_up_database,
    azurerm_logic_app_action_http.scale_down_database
  ]
}

# Role Assignments for Logic App Managed Identity

# SQL DB Contributor role for database scaling operations
resource "azurerm_role_assignment" "logic_app_sql_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "SQL DB Contributor"
  principal_id         = azurerm_logic_app_workflow.scaling.identity[0].principal_id
  
  depends_on = [azurerm_logic_app_workflow.scaling]
}

# Contributor role for reading database configuration
resource "azurerm_role_assignment" "logic_app_contributor" {
  scope                = azurerm_mssql_database.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_logic_app_workflow.scaling.identity[0].principal_id
  
  depends_on = [azurerm_logic_app_workflow.scaling]
}

# Key Vault Secrets User role for accessing credentials
resource "azurerm_role_assignment" "logic_app_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_logic_app_workflow.scaling.identity[0].principal_id
  
  depends_on = [azurerm_logic_app_workflow.scaling]
}

# Log Analytics Contributor for scaling operation logging
resource "azurerm_role_assignment" "logic_app_log_analytics" {
  scope                = azurerm_log_analytics_workspace.main.id
  role_definition_name = "Log Analytics Contributor"
  principal_id         = azurerm_logic_app_workflow.scaling.identity[0].principal_id
  
  depends_on = [azurerm_logic_app_workflow.scaling]
}

# Current user Key Vault Administrator role (for secret creation)
resource "azurerm_role_assignment" "current_user_kv_admin" {
  count = var.enable_key_vault_rbac ? 1 : 0
  
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Diagnostic Settings for comprehensive monitoring
resource "azurerm_monitor_diagnostic_setting" "sql_database" {
  name                       = "sql-database-diagnostics"
  target_resource_id         = azurerm_mssql_database.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Database-specific logs
  enabled_log {
    category = "SQLInsights"
  }
  
  enabled_log {
    category = "AutomaticTuning"
  }
  
  enabled_log {
    category = "QueryStoreRuntimeStatistics"
  }
  
  enabled_log {
    category = "QueryStoreWaitStatistics"
  }
  
  enabled_log {
    category = "Errors"
  }
  
  enabled_log {
    category = "DatabaseWaitStatistics"
  }
  
  enabled_log {
    category = "Timeouts"
  }
  
  enabled_log {
    category = "Blocks"
  }
  
  enabled_log {
    category = "Deadlocks"
  }
  
  # Database-specific metrics
  metric {
    category = "Basic"
    enabled  = true
  }
  
  metric {
    category = "InstanceAndAppAdvanced"
    enabled  = var.enable_detailed_monitoring
  }
  
  metric {
    category = "WorkloadManagement"
    enabled  = var.enable_detailed_monitoring
  }
}

resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  name                       = "logic-app-diagnostics"
  target_resource_id         = azurerm_logic_app_workflow.scaling.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Logic Apps logs
  enabled_log {
    category = "WorkflowRuntime"
  }
  
  # Logic Apps metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Cost Budget Alert (if enabled)
resource "azurerm_consumption_budget_resource_group" "main" {
  count = var.enable_cost_alerts ? 1 : 0
  
  name              = "budget-${local.resource_prefix}-${local.resource_suffix}"
  resource_group_id = azurerm_resource_group.main.id
  
  amount     = var.monthly_budget_limit
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
  }
  
  notification {
    enabled        = true
    threshold      = 80
    operator       = "EqualTo"
    threshold_type = "Actual"
    
    contact_emails = var.alert_email_recipients
  }
  
  notification {
    enabled        = true
    threshold      = 100
    operator       = "EqualTo"
    threshold_type = "Forecasted"
    
    contact_emails = var.alert_email_recipients
  }
}