# Main Terraform configuration for Azure Playwright Testing with Application Insights

# Data sources for current Azure context
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for globally unique names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Generate random password for test user if not provided
resource "random_password" "test_password" {
  count   = var.test_password == "" ? 1 : 0
  length  = 16
  special = true
}

# Local values for resource naming
locals {
  suffix                       = random_string.suffix.result
  application_insights_name    = var.application_insights_name != "" ? var.application_insights_name : "ai-${var.project_name}-${local.suffix}"
  key_vault_name              = var.key_vault_name != "" ? var.key_vault_name : "kv-${var.project_name}-${local.suffix}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-${var.project_name}-${local.suffix}"
  test_password               = var.test_password != "" ? var.test_password : random_password.test_password[0].result
  
  # Common tags to be applied to all resources
  common_tags = merge(var.tags, {
    CreatedBy = "terraform"
    Timestamp = timestamp()
  })
}

#####################################
# Resource Group
#####################################

resource "azurerm_resource_group" "playwright_testing" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

#####################################
# Log Analytics Workspace
#####################################

# Log Analytics workspace for Application Insights
resource "azurerm_log_analytics_workspace" "playwright" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.playwright_testing.location
  resource_group_name = azurerm_resource_group.playwright_testing.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.common_tags, {
    Component = "log-analytics"
    Purpose   = "application-insights-backend"
  })
}

#####################################
# Application Insights
#####################################

# Application Insights for monitoring and telemetry
resource "azurerm_application_insights" "playwright" {
  name                = local.application_insights_name
  location            = azurerm_resource_group.playwright_testing.location
  resource_group_name = azurerm_resource_group.playwright_testing.name
  workspace_id        = azurerm_log_analytics_workspace.playwright.id
  application_type    = var.application_type
  retention_in_days   = var.retention_in_days
  
  tags = merge(local.common_tags, {
    Component = "application-insights"
    Purpose   = "test-monitoring"
  })
}

#####################################
# Key Vault
#####################################

# Key Vault for secure storage of test credentials and secrets
resource "azurerm_key_vault" "playwright" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.playwright_testing.location
  resource_group_name        = azurerm_resource_group.playwright_testing.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  enable_rbac_authorization  = var.enable_rbac_authorization
  purge_protection_enabled   = false # Set to true for production
  soft_delete_retention_days = 7     # Minimum value for testing
  
  # Network access rules
  network_acls {
    default_action = "Allow" # Consider restricting to specific networks in production
    bypass         = "AzureServices"
  }
  
  tags = merge(local.common_tags, {
    Component = "key-vault"
    Purpose   = "secrets-management"
  })
}

# Role assignment for current user to manage Key Vault secrets
resource "azurerm_role_assignment" "key_vault_secrets_officer" {
  scope                = azurerm_key_vault.playwright.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Wait for role assignment to propagate
resource "time_sleep" "wait_for_rbac" {
  depends_on      = [azurerm_role_assignment.key_vault_secrets_officer]
  create_duration = "30s"
}

#####################################
# Key Vault Secrets
#####################################

# Store Application Insights connection string
resource "azurerm_key_vault_secret" "app_insights_connection_string" {
  name         = "AppInsightsConnectionString"
  value        = azurerm_application_insights.playwright.connection_string
  key_vault_id = azurerm_key_vault.playwright.id
  
  depends_on = [time_sleep.wait_for_rbac]
  
  tags = {
    Component = "application-insights"
    Type      = "connection-string"
  }
}

# Store test application URL
resource "azurerm_key_vault_secret" "test_app_url" {
  name         = "TestAppUrl"
  value        = var.test_app_url
  key_vault_id = azurerm_key_vault.playwright.id
  
  depends_on = [time_sleep.wait_for_rbac]
  
  tags = {
    Component = "test-config"
    Type      = "url"
  }
}

# Store test username
resource "azurerm_key_vault_secret" "test_username" {
  name         = "TestUsername"
  value        = var.test_username
  key_vault_id = azurerm_key_vault.playwright.id
  
  depends_on = [time_sleep.wait_for_rbac]
  
  tags = {
    Component = "test-config"
    Type      = "username"
  }
}

# Store test password
resource "azurerm_key_vault_secret" "test_password" {
  name         = "TestPassword"
  value        = local.test_password
  key_vault_id = azurerm_key_vault.playwright.id
  
  depends_on = [time_sleep.wait_for_rbac]
  
  tags = {
    Component = "test-config"
    Type      = "password"
  }
}

#####################################
# Monitoring and Alerting
#####################################

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "playwright_alerts" {
  name                = "ag-playwright-alerts"
  resource_group_name = azurerm_resource_group.playwright_testing.name
  short_name          = "playwrght"
  
  tags = merge(local.common_tags, {
    Component = "monitoring"
    Purpose   = "alerting"
  })
}

# Metric Alert for high test failure rate
resource "azurerm_monitor_metric_alert" "high_failure_rate" {
  name                = "High Test Failure Rate"
  resource_group_name = azurerm_resource_group.playwright_testing.name
  scopes              = [azurerm_application_insights.playwright.id]
  description         = "Alert when test failure rate exceeds 20%"
  enabled             = true
  auto_mitigate       = true
  frequency           = "PT1M"
  severity            = 2
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "customMetrics/TestFailureRate"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 20
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.playwright_alerts.id
  }
  
  tags = merge(local.common_tags, {
    Component = "monitoring"
    Type      = "metric-alert"
  })
}

#####################################
# Optional: Storage Account for Test Artifacts
#####################################

# Storage account for storing test artifacts (screenshots, videos, reports)
resource "azurerm_storage_account" "playwright_artifacts" {
  name                     = "st${replace(local.suffix, "-", "")}playwright"
  resource_group_name      = azurerm_resource_group.playwright_testing.name
  location                 = azurerm_resource_group.playwright_testing.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Enable versioning and soft delete for artifact retention
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = merge(local.common_tags, {
    Component = "storage"
    Purpose   = "test-artifacts"
  })
}

# Container for test screenshots
resource "azurerm_storage_container" "screenshots" {
  name                  = "screenshots"
  storage_account_name  = azurerm_storage_account.playwright_artifacts.name
  container_access_type = "private"
}

# Container for test videos
resource "azurerm_storage_container" "videos" {
  name                  = "videos"
  storage_account_name  = azurerm_storage_account.playwright_artifacts.name
  container_access_type = "private"
}

# Container for test reports
resource "azurerm_storage_container" "reports" {
  name                  = "reports"
  storage_account_name  = azurerm_storage_account.playwright_artifacts.name
  container_access_type = "private"
}

# Store storage account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "StorageConnectionString"
  value        = azurerm_storage_account.playwright_artifacts.primary_connection_string
  key_vault_id = azurerm_key_vault.playwright.id
  
  depends_on = [time_sleep.wait_for_rbac]
  
  tags = {
    Component = "storage"
    Type      = "connection-string"
  }
}

#####################################
# Outputs and Data Export
#####################################

# Output key information for CI/CD integration
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    resource_group_name      = azurerm_resource_group.playwright_testing.name
    location                 = azurerm_resource_group.playwright_testing.location
    application_insights_name = azurerm_application_insights.playwright.name
    key_vault_name          = azurerm_key_vault.playwright.name
    storage_account_name    = azurerm_storage_account.playwright_artifacts.name
  }
}