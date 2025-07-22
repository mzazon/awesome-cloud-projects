# Main Terraform Configuration for Azure Static Web Apps and Azure Functions
# This file contains the core infrastructure resources for the full-stack serverless application

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Storage Account for data persistence
resource "azurerm_storage_account" "main" {
  name                = var.storage_account_name != "" ? var.storage_account_name : "st${var.project_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Storage configuration
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = var.storage_account_kind
  access_tier              = var.storage_account_access_tier
  
  # Security configuration
  enable_https_traffic_only      = var.enable_https_only
  min_tls_version               = "TLS1_2"
  allow_nested_items_to_be_public = var.enable_public_access
  
  # Public access configuration
  public_network_access_enabled = true
  
  # Blob properties for enhanced security
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "POST", "PUT", "DELETE"]
      allowed_origins    = length(var.allowed_origins) > 0 ? var.allowed_origins : ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
    
    versioning_enabled = true
  }
  
  # Queue properties
  queue_properties {
    logging {
      delete                = true
      read                  = true
      write                 = true
      version               = "1.0"
      retention_policy_days = 10
    }
    
    hour_metrics {
      enabled               = true
      include_apis          = true
      version               = "1.0"
      retention_policy_days = 10
    }
    
    minute_metrics {
      enabled               = true
      include_apis          = true
      version               = "1.0"
      retention_policy_days = 10
    }
  }
  
  tags = var.tags
}

# Create Storage Table for task data
resource "azurerm_storage_table" "tasks" {
  name                 = "tasks"
  storage_account_name = azurerm_storage_account.main.name
  
  depends_on = [azurerm_storage_account.main]
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  sku               = "PerGB2018"
  retention_in_days = var.log_analytics_workspace_retention_days
  
  tags = var.tags
}

# Create Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "appi-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  application_type    = var.application_insights_type
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  
  tags = var.tags
}

# Create Azure Static Web App
resource "azurerm_static_web_app" "main" {
  name                = var.static_web_app_name != "" ? var.static_web_app_name : "swa-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  sku_tier = var.static_web_app_sku
  sku_size = var.static_web_app_sku
  
  tags = var.tags
}

# Configure Static Web App with repository (optional)
resource "azurerm_static_web_app_source_control" "main" {
  count = var.github_repository_url != "" ? 1 : 0
  
  static_web_app_id   = azurerm_static_web_app.main.id
  repository_url      = var.github_repository_url
  branch              = var.github_branch
  
  build_properties {
    app_location     = var.app_location
    api_location     = var.api_location
    output_location  = var.output_location
  }
}

# Create custom domain for Static Web App (optional)
resource "azurerm_static_web_app_custom_domain" "main" {
  count = var.enable_custom_domain && var.custom_domain_name != "" ? 1 : 0
  
  static_web_app_id = azurerm_static_web_app.main.id
  domain_name       = var.custom_domain_name
  domain_type       = "Standard"
}

# Configure Static Web App settings
resource "azurerm_static_web_app_function_app_registration" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  static_web_app_id = azurerm_static_web_app.main.id
  function_app_id   = azurerm_static_web_app.main.id
}

# Create Storage Account Management Policy for cost optimization
resource "azurerm_storage_management_policy" "main" {
  count = var.enable_cost_optimization && var.storage_lifecycle_policy ? 1 : 0
  
  storage_account_id = azurerm_storage_account.main.id
  
  rule {
    name    = "rule-delete-old-blobs"
    enabled = true
    filters {
      prefix_match = ["logs/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
    }
  }
  
  rule {
    name    = "rule-tier-cool-blobs"
    enabled = true
    filters {
      prefix_match = ["archive/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 7
        tier_to_archive_after_days_since_modification_greater_than = 30
      }
    }
  }
}

# Create backup vault for storage account (optional)
resource "azurerm_data_protection_backup_vault" "main" {
  count = var.enable_backup ? 1 : 0
  
  name                = "bv-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  datastore_type = "VaultStore"
  redundancy     = "LocallyRedundant"
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
}

# Create backup policy for storage account (optional)
resource "azurerm_data_protection_backup_policy_blob_storage" "main" {
  count = var.enable_backup ? 1 : 0
  
  name     = "policy-${var.project_name}-${var.environment}"
  vault_id = azurerm_data_protection_backup_vault.main[0].id
  
  retention_duration = "P${var.backup_retention_days}D"
  
  depends_on = [azurerm_data_protection_backup_vault.main]
}

# Create Key Vault for secrets management (optional for production)
resource "azurerm_key_vault" "main" {
  count = var.environment == "prod" ? 1 : 0
  
  name                       = "kv-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore"
    ]
    
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
    ]
    
    certificate_permissions = [
      "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore"
    ]
  }
  
  tags = var.tags
}

# Store Storage Account Connection String in Key Vault (optional for production)
resource "azurerm_key_vault_secret" "storage_connection_string" {
  count = var.environment == "prod" ? 1 : 0
  
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main[0].id
  
  depends_on = [azurerm_key_vault.main]
}

# Create Network Security Group for enhanced security (optional)
resource "azurerm_network_security_group" "main" {
  count = var.environment == "prod" ? 1 : 0
  
  name                = "nsg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = var.tags
}

# Create Alert Rules for monitoring (optional)
resource "azurerm_monitor_action_group" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "ag-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ag-${var.project_name}"
  
  tags = var.tags
}

# Create metric alert for storage account
resource "azurerm_monitor_metric_alert" "storage_availability" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "alert-storage-availability-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_storage_account.main.id]
  description         = "Alert when storage account availability is below 99%"
  
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "Availability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 99
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  frequency   = "PT1M"
  window_size = "PT5M"
  
  tags = var.tags
}

# Create diagnostic settings for storage account
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count = var.enable_application_insights ? 1 : 0
  
  name               = "diag-${var.project_name}-storage-${var.environment}"
  target_resource_id = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
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
    category = "Transaction"
    enabled  = true
  }
  
  depends_on = [azurerm_log_analytics_workspace.main]
}

# Create diagnostic settings for Static Web App
resource "azurerm_monitor_diagnostic_setting" "static_web_app" {
  count = var.enable_application_insights ? 1 : 0
  
  name               = "diag-${var.project_name}-swa-${var.environment}"
  target_resource_id = azurerm_static_web_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
  
  depends_on = [azurerm_log_analytics_workspace.main]
}

# Create role assignment for Static Web App to access Storage Account
resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_static_web_app.main.identity[0].principal_id
  
  depends_on = [azurerm_static_web_app.main]
}

# Create role assignment for Static Web App to access Table Storage
resource "azurerm_role_assignment" "table_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_static_web_app.main.identity[0].principal_id
  
  depends_on = [azurerm_static_web_app.main]
}

# Add delay to ensure resources are fully provisioned
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_storage_account.main,
    azurerm_storage_table.tasks,
    azurerm_static_web_app.main
  ]
  
  create_duration = "30s"
}