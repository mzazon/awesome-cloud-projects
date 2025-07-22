# Data sources for current Azure context
data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create resource group for AI governance infrastructure
resource "azurerm_resource_group" "ai_governance" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Log Analytics workspace for centralized logging
resource "azurerm_log_analytics_workspace" "ai_governance" {
  name                = "${var.name_prefix}-law-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# Create Application Insights for Logic Apps monitoring
resource "azurerm_application_insights" "ai_governance" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "${var.name_prefix}-ai-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  workspace_id        = azurerm_log_analytics_workspace.ai_governance.id
  application_type    = "web"
  tags                = var.tags
}

# Create Key Vault for secure credential storage
resource "azurerm_key_vault" "ai_governance" {
  name                        = "${var.name_prefix}-kv-${random_string.suffix.result}"
  location                    = azurerm_resource_group.ai_governance.location
  resource_group_name         = azurerm_resource_group.ai_governance.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.key_vault_sku
  soft_delete_retention_days  = var.key_vault_soft_delete_retention_days
  purge_protection_enabled    = var.key_vault_purge_protection_enabled
  enable_rbac_authorization   = true
  
  tags = var.tags
}

# Create Key Vault access policy for current user
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.ai_governance.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Create", "Delete", "Get", "List", "Purge", "Recover", "Update"
  ]

  secret_permissions = [
    "Delete", "Get", "List", "Purge", "Recover", "Set"
  ]

  certificate_permissions = [
    "Create", "Delete", "Get", "List", "Purge", "Recover", "Update"
  ]
}

# Create storage account for reports and audit logs
resource "azurerm_storage_account" "ai_governance" {
  name                     = "${var.name_prefix}st${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.ai_governance.name
  location                 = azurerm_resource_group.ai_governance.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  min_tls_version          = "TLS1_2"
  
  blob_properties {
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }
  
  tags = var.tags
}

# Create blob container for compliance reports
resource "azurerm_storage_container" "reports" {
  name                  = "reports"
  storage_account_name  = azurerm_storage_account.ai_governance.name
  container_access_type = "private"
}

# Create blob container for audit logs
resource "azurerm_storage_container" "audit_logs" {
  name                  = "audit-logs"
  storage_account_name  = azurerm_storage_account.ai_governance.name
  container_access_type = "private"
}

# Create managed identity for Logic Apps
resource "azurerm_user_assigned_identity" "logic_app_identity" {
  name                = "${var.name_prefix}-logic-identity-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  tags                = var.tags
}

# Grant Logic Apps managed identity access to Key Vault
resource "azurerm_role_assignment" "logic_app_keyvault" {
  scope                = azurerm_key_vault.ai_governance.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.logic_app_identity.principal_id
}

# Grant Logic Apps managed identity access to storage account
resource "azurerm_role_assignment" "logic_app_storage" {
  scope                = azurerm_storage_account.ai_governance.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.logic_app_identity.principal_id
}

# Grant Logic Apps managed identity access to Log Analytics
resource "azurerm_role_assignment" "logic_app_logs" {
  scope                = azurerm_log_analytics_workspace.ai_governance.id
  role_definition_name = "Log Analytics Contributor"
  principal_id         = azurerm_user_assigned_identity.logic_app_identity.principal_id
}

# Grant Logic Apps managed identity Graph API permissions for reading applications
resource "azuread_app_role_assignment" "logic_app_graph" {
  app_role_id         = "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30" # Application.Read.All
  principal_object_id = azurerm_user_assigned_identity.logic_app_identity.principal_id
  resource_object_id  = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
}

# Logic App for agent lifecycle management
resource "azurerm_logic_app_workflow" "agent_lifecycle" {
  name                = "${var.name_prefix}-lifecycle-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.logic_app_identity.id]
  }
  
  workflow_parameters = {
    "$connections" = jsonencode({
      "azureloganalytics" = {
        "connectionId"   = azurerm_api_connection.log_analytics.id
        "connectionName" = azurerm_api_connection.log_analytics.name
        "id"             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.ai_governance.location}/managedApis/azureloganalytics"
      }
    })
  }
  
  tags = var.tags
}

# Logic App for compliance monitoring
resource "azurerm_logic_app_workflow" "compliance_monitoring" {
  count               = var.logic_app_compliance_monitoring_enabled ? 1 : 0
  name                = "${var.name_prefix}-compliance-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.logic_app_identity.id]
  }
  
  workflow_parameters = {
    "$connections" = jsonencode({
      "azureloganalytics" = {
        "connectionId"   = azurerm_api_connection.log_analytics.id
        "connectionName" = azurerm_api_connection.log_analytics.name
        "id"             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.ai_governance.location}/managedApis/azureloganalytics"
      }
    })
  }
  
  tags = var.tags
}

# Logic App for access control automation
resource "azurerm_logic_app_workflow" "access_control" {
  count               = var.logic_app_access_control_enabled ? 1 : 0
  name                = "${var.name_prefix}-access-control-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.logic_app_identity.id]
  }
  
  workflow_parameters = {
    "$connections" = jsonencode({
      "azuread" = {
        "connectionId"   = azurerm_api_connection.azuread.id
        "connectionName" = azurerm_api_connection.azuread.name
        "id"             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.ai_governance.location}/managedApis/azuread"
      }
    })
  }
  
  tags = var.tags
}

# Logic App for audit and reporting
resource "azurerm_logic_app_workflow" "audit_reporting" {
  name                = "${var.name_prefix}-audit-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.logic_app_identity.id]
  }
  
  workflow_parameters = {
    "$connections" = jsonencode({
      "azureloganalytics" = {
        "connectionId"   = azurerm_api_connection.log_analytics.id
        "connectionName" = azurerm_api_connection.log_analytics.name
        "id"             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.ai_governance.location}/managedApis/azureloganalytics"
      }
      "azureblob" = {
        "connectionId"   = azurerm_api_connection.storage_blob.id
        "connectionName" = azurerm_api_connection.storage_blob.name
        "id"             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.ai_governance.location}/managedApis/azureblob"
      }
    })
  }
  
  tags = var.tags
}

# Logic App for performance monitoring
resource "azurerm_logic_app_workflow" "performance_monitoring" {
  name                = "${var.name_prefix}-monitoring-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.logic_app_identity.id]
  }
  
  workflow_parameters = {
    "$connections" = jsonencode({
      "azureloganalytics" = {
        "connectionId"   = azurerm_api_connection.log_analytics.id
        "connectionName" = azurerm_api_connection.log_analytics.name
        "id"             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.ai_governance.location}/managedApis/azureloganalytics"
      }
    })
  }
  
  tags = var.tags
}

# API Connection for Log Analytics
resource "azurerm_api_connection" "log_analytics" {
  name                = "${var.name_prefix}-loganalytics-conn-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.ai_governance.location}/managedApis/azureloganalytics"
  
  parameter_values = {
    "username"    = azurerm_log_analytics_workspace.ai_governance.workspace_id
    "password"    = azurerm_log_analytics_workspace.ai_governance.primary_shared_key
    "gateway"     = ""
    "encryptConnection" = "False"
    "privacySetting" = "None"
  }
  
  tags = var.tags
}

# API Connection for Azure AD
resource "azurerm_api_connection" "azuread" {
  name                = "${var.name_prefix}-azuread-conn-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.ai_governance.location}/managedApis/azuread"
  
  tags = var.tags
}

# API Connection for Azure Blob Storage
resource "azurerm_api_connection" "storage_blob" {
  name                = "${var.name_prefix}-blob-conn-${random_string.suffix.result}"
  location            = azurerm_resource_group.ai_governance.location
  resource_group_name = azurerm_resource_group.ai_governance.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.ai_governance.location}/managedApis/azureblob"
  
  parameter_values = {
    "accountName" = azurerm_storage_account.ai_governance.name
    "accessKey"   = azurerm_storage_account.ai_governance.primary_access_key
  }
  
  tags = var.tags
}

# Logic App trigger for agent lifecycle management
resource "azurerm_logic_app_trigger_recurrence" "agent_lifecycle" {
  name         = "agent-lifecycle-trigger"
  logic_app_id = azurerm_logic_app_workflow.agent_lifecycle.id
  frequency    = var.logic_app_lifecycle_schedule.frequency
  interval     = var.logic_app_lifecycle_schedule.interval
}

# Logic App trigger for daily audit reporting
resource "azurerm_logic_app_trigger_recurrence" "audit_reporting" {
  name         = "audit-reporting-trigger"
  logic_app_id = azurerm_logic_app_workflow.audit_reporting.id
  frequency    = var.logic_app_audit_schedule.frequency
  interval     = var.logic_app_audit_schedule.interval
  start_time   = var.logic_app_audit_schedule.start_time
}

# Logic App trigger for performance monitoring
resource "azurerm_logic_app_trigger_recurrence" "performance_monitoring" {
  name         = "performance-monitoring-trigger"
  logic_app_id = azurerm_logic_app_workflow.performance_monitoring.id
  frequency    = "Minute"
  interval     = var.logic_app_monitoring_interval
}

# Azure Monitor Action Group for governance alerts
resource "azurerm_monitor_action_group" "ai_governance" {
  name                = "${var.name_prefix}-alerts-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.ai_governance.name
  short_name          = "ai-gov"
  
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
  
  tags = var.tags
}

# Azure Monitor Alert for Logic App failures
resource "azurerm_monitor_metric_alert" "logic_app_failures" {
  name                = "${var.name_prefix}-logic-app-failures-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.ai_governance.name
  scopes              = [azurerm_logic_app_workflow.agent_lifecycle.id]
  description         = "Alert when Logic App workflow failures exceed threshold"
  severity            = var.alert_severity_level
  
  criteria {
    metric_namespace = "Microsoft.Logic/workflows"
    metric_name      = "RunsFailed"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 3
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.ai_governance.id
  }
  
  tags = var.tags
}

# Azure Monitor Alert for Key Vault access anomalies
resource "azurerm_monitor_metric_alert" "keyvault_access" {
  name                = "${var.name_prefix}-keyvault-access-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.ai_governance.name
  scopes              = [azurerm_key_vault.ai_governance.id]
  description         = "Alert on unusual Key Vault access patterns"
  severity            = var.alert_severity_level
  
  criteria {
    metric_namespace = "Microsoft.KeyVault/vaults"
    metric_name      = "ServiceApiResult"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 100
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.ai_governance.id
  }
  
  tags = var.tags
}

# Cost Management Budget for AI governance resources
resource "azurerm_consumption_budget_resource_group" "ai_governance" {
  count               = var.enable_cost_alerts ? 1 : 0
  name                = "${var.name_prefix}-budget-${random_string.suffix.result}"
  resource_group_id   = azurerm_resource_group.ai_governance.id
  
  amount     = var.monthly_budget_amount
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01", timestamp())
    end_date   = formatdate("YYYY-MM-01", timeadd(timestamp(), "8760h"))
  }
  
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    
    contact_emails = var.alert_email_addresses
  }
  
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    
    contact_emails = var.alert_email_addresses
  }
}