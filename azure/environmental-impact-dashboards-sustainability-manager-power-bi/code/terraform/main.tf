# =============================================================================
# Azure Environmental Impact Dashboards with Sustainability Manager and Power BI
# =============================================================================
# This Terraform configuration creates the infrastructure for environmental
# impact tracking and sustainability reporting using Azure Sustainability Manager
# and Power BI integration.

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Current client configuration for tenant and subscription information
data "azurerm_client_config" "current" {}

# Local values for consistent naming and tagging
locals {
  suffix = random_id.suffix.hex
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-sustainability-${local.suffix}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Purpose      = "sustainability"
    ManagedBy    = "terraform"
    Solution     = "environmental-impact-dashboards"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Naming conventions
  storage_account_name = "stsustain${local.suffix}"
  key_vault_name      = "kv-sustain-${local.suffix}"
  function_app_name   = "func-sustainability-${local.suffix}"
  data_factory_name   = "adf-sustainability-${local.suffix}"
  law_name           = "law-sustainability-${local.suffix}"
  app_insights_name  = "ai-sustainability-${local.suffix}"
  logic_app_name     = "la-sustainability-${local.suffix}"
  asp_name           = "asp-powerbi-${local.suffix}"
}

# ============================================================================
# CORE INFRASTRUCTURE
# ============================================================================

# Resource Group for all sustainability resources
resource "azurerm_resource_group" "sustainability" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ============================================================================
# STORAGE AND DATA LAYER
# ============================================================================

# Storage Account for sustainability data lake
resource "azurerm_storage_account" "sustainability_data" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.sustainability.name
  location                 = azurerm_resource_group.sustainability.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Security configurations
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  public_network_access_enabled   = var.enable_public_access
  
  # Advanced threat protection
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    change_feed_retention_in_days = var.retention_days
    
    delete_retention_policy {
      days = var.retention_days
    }
    
    container_delete_retention_policy {
      days = var.retention_days
    }
  }
  
  # Network access rules (restrict to Azure services when public access is disabled)
  dynamic "network_rules" {
    for_each = var.enable_public_access ? [] : [1]
    content {
      default_action = "Deny"
      bypass         = ["AzureServices"]
      ip_rules       = []
    }
  }
  
  tags = local.common_tags
}

# Storage Container for raw sustainability data
resource "azurerm_storage_container" "sustainability_data" {
  name                  = "sustainability-data"
  storage_account_name  = azurerm_storage_account.sustainability_data.name
  container_access_type = "private"
}

# Storage Container for processed emissions data
resource "azurerm_storage_container" "emissions_data" {
  name                  = "emissions-data"
  storage_account_name  = azurerm_storage_account.sustainability_data.name
  container_access_type = "private"
}

# Storage Container for Power BI datasets
resource "azurerm_storage_container" "powerbi_data" {
  name                  = "powerbi-data"
  storage_account_name  = azurerm_storage_account.sustainability_data.name
  container_access_type = "private"
}

# ============================================================================
# MONITORING AND LOGGING
# ============================================================================

# Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "sustainability" {
  name                = local.law_name
  location            = azurerm_resource_group.sustainability.location
  resource_group_name = azurerm_resource_group.sustainability.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.retention_days
  
  tags = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "sustainability" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.sustainability.location
  resource_group_name = azurerm_resource_group.sustainability.name
  workspace_id        = azurerm_log_analytics_workspace.sustainability.id
  application_type    = "web"
  
  tags = local.common_tags
}

# ============================================================================
# SECURITY AND SECRETS MANAGEMENT
# ============================================================================

# Key Vault for storing sensitive configuration and credentials
resource "azurerm_key_vault" "sustainability" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.sustainability.location
  resource_group_name        = azurerm_resource_group.sustainability.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  # Enable Azure services access
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_access
  
  dynamic "network_acls" {
    for_each = var.enable_public_access ? [] : [1]
    content {
      default_action = "Deny"
      bypass         = "AzureServices"
      ip_rules       = []
    }
  }
  
  tags = local.common_tags
}

# Key Vault Access Policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.sustainability.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Import", "Backup", "Restore", "Recover"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Import", "Backup", "Restore", "Recover"
  ]
}

# Store storage account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.sustainability_data.primary_connection_string
  key_vault_id = azurerm_key_vault.sustainability.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = local.common_tags
}

# Store Application Insights instrumentation key
resource "azurerm_key_vault_secret" "app_insights_key" {
  name         = "application-insights-key"
  value        = azurerm_application_insights.sustainability.instrumentation_key
  key_vault_id = azurerm_key_vault.sustainability.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = local.common_tags
}

# ============================================================================
# DATA PROCESSING INFRASTRUCTURE
# ============================================================================

# Data Factory for data ingestion and orchestration
resource "azurerm_data_factory" "sustainability" {
  name                = local.data_factory_name
  location            = var.data_factory_location != "" ? var.data_factory_location : azurerm_resource_group.sustainability.location
  resource_group_name = azurerm_resource_group.sustainability.name
  
  # Enable managed identity for secure resource access
  identity {
    type = "SystemAssigned"
  }
  
  # Integration with monitoring services
  monitoring_enabled = var.enable_monitoring
  
  tags = local.common_tags
}

# Data Factory Linked Service for Storage Account
resource "azurerm_data_factory_linked_service_azure_blob_storage" "sustainability_storage" {
  name            = "ls-sustainability-storage"
  data_factory_id = azurerm_data_factory.sustainability.id
  
  # Use managed identity for authentication
  use_managed_identity = true
  service_endpoint     = azurerm_storage_account.sustainability_data.primary_blob_endpoint
}

# App Service Plan for Function Apps (Consumption Plan for cost optimization)
resource "azurerm_service_plan" "sustainability" {
  name                = local.asp_name
  location            = azurerm_resource_group.sustainability.location
  resource_group_name = azurerm_resource_group.sustainability.name
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
  
  tags = local.common_tags
}

# Function App for emissions calculations and data processing
resource "azurerm_linux_function_app" "emissions_calculator" {
  name                = local.function_app_name
  location            = azurerm_resource_group.sustainability.location
  resource_group_name = azurerm_resource_group.sustainability.name
  service_plan_id     = azurerm_service_plan.sustainability.id
  
  storage_account_name       = azurerm_storage_account.sustainability_data.name
  storage_account_access_key = azurerm_storage_account.sustainability_data.primary_access_key
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Site configuration
  site_config {
    application_insights_key               = azurerm_application_insights.sustainability.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.sustainability.connection_string
    
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # Security configurations
    ftps_state                = "Disabled"
    http2_enabled            = true
    minimum_tls_version      = "1.2"
    use_32_bit_worker        = false
    always_on                = false  # Not available for Consumption Plan
  }
  
  # Application settings for emissions calculations
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "EMISSIONS_FACTOR_SOURCE"      = var.emissions_factor_source
    "CALCULATION_METHOD"           = var.emissions_calculation_method
    "SUSTAINABILITY_SCOPES"        = join(",", var.sustainability_scopes)
    "STORAGE_CONNECTION_STRING"    = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.sustainability.name};SecretName=${azurerm_key_vault_secret.storage_connection_string.name})"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.sustainability.name};SecretName=${azurerm_key_vault_secret.app_insights_key.name})"
    "KEY_VAULT_NAME"              = azurerm_key_vault.sustainability.name
    "RETENTION_DAYS"              = var.retention_days
  }
  
  tags = local.common_tags
}

# Key Vault Access Policy for Function App Managed Identity
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.sustainability.id
  tenant_id    = azurerm_linux_function_app.emissions_calculator.identity[0].tenant_id
  object_id    = azurerm_linux_function_app.emissions_calculator.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
}

# ============================================================================
# AUTOMATION AND ORCHESTRATION
# ============================================================================

# Logic App for automated data refresh and orchestration
resource "azurerm_logic_app_workflow" "sustainability_automation" {
  name                = local.logic_app_name
  location            = azurerm_resource_group.sustainability.location
  resource_group_name = azurerm_resource_group.sustainability.name
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Workflow definition for daily data refresh
  workflow_schema   = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"
  
  tags = local.common_tags
}

# ============================================================================
# MONITORING AND ALERTING
# ============================================================================

# Action Group for sustainability alerts
resource "azurerm_monitor_action_group" "sustainability_alerts" {
  count               = var.enable_monitoring && length(var.alert_email_recipients) > 0 ? 1 : 0
  name                = "ag-sustainability-alerts"
  resource_group_name = azurerm_resource_group.sustainability.name
  short_name          = "SustainAlert"
  
  dynamic "email_receiver" {
    for_each = var.alert_email_recipients
    content {
      name          = "EmailAlert-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
  
  tags = local.common_tags
}

# Metric Alert for Function App failures
resource "azurerm_monitor_metric_alert" "function_app_failures" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "alert-function-app-failures"
  resource_group_name = azurerm_resource_group.sustainability.name
  scopes              = [azurerm_linux_function_app.emissions_calculator.id]
  description         = "Alert when Function App execution failures exceed threshold"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }
  
  window_size        = "PT15M"
  frequency          = "PT5M"
  severity           = 2
  
  dynamic "action" {
    for_each = length(var.alert_email_recipients) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.sustainability_alerts[0].id
    }
  }
  
  tags = local.common_tags
}

# Metric Alert for Storage Account capacity
resource "azurerm_monitor_metric_alert" "storage_capacity" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "alert-storage-capacity"
  resource_group_name = azurerm_resource_group.sustainability.name
  scopes              = [azurerm_storage_account.sustainability_data.id]
  description         = "Alert when storage capacity exceeds 80% of allocated space"
  
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "UsedCapacity"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 858993459200  # 800GB in bytes
  }
  
  window_size        = "PT1H"
  frequency          = "PT15M"
  severity           = 1
  
  dynamic "action" {
    for_each = length(var.alert_email_recipients) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.sustainability_alerts[0].id
    }
  }
  
  tags = local.common_tags
}

# ============================================================================
# RBAC AND PERMISSIONS
# ============================================================================

# Storage Blob Data Contributor role for Function App
resource "azurerm_role_assignment" "function_app_storage_contributor" {
  scope                = azurerm_storage_account.sustainability_data.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.emissions_calculator.identity[0].principal_id
}

# Storage Blob Data Contributor role for Data Factory
resource "azurerm_role_assignment" "data_factory_storage_contributor" {
  scope                = azurerm_storage_account.sustainability_data.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.sustainability.identity[0].principal_id
}

# Logic App Contributor role for automation workflows
resource "azurerm_role_assignment" "logic_app_contributor" {
  scope                = azurerm_resource_group.sustainability.id
  role_definition_name = "Logic App Contributor"
  principal_id         = azurerm_logic_app_workflow.sustainability_automation.identity[0].principal_id
}

# ============================================================================
# DIAGNOSTIC SETTINGS
# ============================================================================

# Diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app_diagnostics" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "diag-${local.function_app_name}"
  target_resource_id = azurerm_linux_function_app.emissions_calculator.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.sustainability.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_diagnostics" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "diag-${local.storage_account_name}"
  target_resource_id = azurerm_storage_account.sustainability_data.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.sustainability.id
  
  enabled_log {
    category = "StorageRead"
  }
  
  enabled_log {
    category = "StorageWrite"
  }
  
  enabled_log {
    category = "StorageDelete"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Key Vault
resource "azurerm_monitor_diagnostic_setting" "key_vault_diagnostics" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "diag-${local.key_vault_name}"
  target_resource_id = azurerm_key_vault.sustainability.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.sustainability.id
  
  enabled_log {
    category = "AuditEvent"
  }
  
  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}