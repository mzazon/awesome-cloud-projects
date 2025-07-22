# Main Terraform Configuration for User Onboarding Workflow
# This file defines the complete Azure infrastructure for automated user onboarding
# using Azure Entra ID, Service Bus, Logic Apps, and Key Vault

# Data sources for existing resources and current configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  # Generate consistent resource names with random suffix
  resource_suffix = random_string.suffix.result
  
  # Resource names with consistent naming convention
  resource_group_name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  key_vault_name         = "kv-${var.project_name}-${local.resource_suffix}"
  service_bus_name       = "sb-${var.project_name}-${local.resource_suffix}"
  storage_account_name   = "st${var.project_name}${local.resource_suffix}"
  logic_app_name         = "la-${var.project_name}-${local.resource_suffix}"
  app_service_plan_name  = "asp-${var.project_name}-${local.resource_suffix}"
  
  # Common tags merged with user-provided tags
  common_tags = merge(var.tags, {
    Environment   = var.environment
    ProjectName   = var.project_name
    ResourceGroup = local.resource_group_name
    DeployedBy    = "terraform"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group - Container for all resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Azure Key Vault - Secure storage for credentials and secrets
resource "azurerm_key_vault" "main" {
  name                            = local.key_vault_name
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = var.key_vault_sku
  
  # Security configuration
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false
  enable_rbac_authorization       = var.enable_rbac_authorization
  purge_protection_enabled        = var.key_vault_purge_protection_enabled
  
  # Soft delete configuration
  soft_delete_retention_days      = var.key_vault_soft_delete_retention_days
  
  # Network access configuration
  network_acls {
    bypass                     = "AzureServices"
    default_action             = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = []
  }
  
  tags = local.common_tags
}

# Key Vault Access Policy for current user (if RBAC is disabled)
resource "azurerm_key_vault_access_policy" "current_user" {
  count = var.enable_rbac_authorization ? 0 : 1
  
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore"
  ]
  
  certificate_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Update",
    "Import"
  ]
  
  key_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Update",
    "Import",
    "Backup",
    "Restore"
  ]
}

# RBAC role assignment for Key Vault Administrator (if RBAC is enabled)
resource "azurerm_role_assignment" "keyvault_admin" {
  count = var.enable_rbac_authorization ? 1 : 0
  
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Service Bus Namespace - Enterprise messaging platform
resource "azurerm_servicebus_namespace" "main" {
  name                = local.service_bus_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.service_bus_sku
  capacity            = var.service_bus_sku == "Premium" ? var.service_bus_capacity : null
  
  tags = local.common_tags
}

# Service Bus Queue - Primary onboarding message queue
resource "azurerm_servicebus_queue" "onboarding" {
  name         = "user-onboarding-queue"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Message handling configuration
  max_delivery_count                    = var.queue_max_delivery_count
  lock_duration                         = var.queue_lock_duration
  default_message_ttl                   = var.queue_message_ttl
  
  # Dead letter queue configuration
  dead_lettering_on_message_expiration  = var.enable_dead_lettering
  
  # Enable duplicate detection for message reliability
  requires_duplicate_detection          = var.enable_duplicate_detection
  duplicate_detection_history_time_window = var.enable_duplicate_detection ? "PT10M" : null
  
  # Enable sessions for ordered processing
  requires_session                      = false
  
  # Partitioning for scalability (Premium only)
  partitioning_enabled                  = var.service_bus_sku == "Premium" ? true : false
}

# Service Bus Topic - Event broadcasting for onboarding events
resource "azurerm_servicebus_topic" "onboarding_events" {
  name         = "user-onboarding-events"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Message configuration
  default_message_ttl                   = var.queue_message_ttl
  
  # Duplicate detection configuration
  requires_duplicate_detection          = var.enable_duplicate_detection
  duplicate_detection_history_time_window = var.enable_duplicate_detection ? "PT10M" : null
  
  # Partitioning for scalability (Premium only)
  partitioning_enabled                  = var.service_bus_sku == "Premium" ? true : false
}

# Service Bus Authorization Rule - Secure access for Logic Apps
resource "azurerm_servicebus_namespace_authorization_rule" "logic_apps" {
  name         = "LogicAppsAccess"
  namespace_id = azurerm_servicebus_namespace.main.id
  
  # Permissions for Logic Apps workflow
  listen = true
  send   = true
  manage = true
}

# Store Service Bus connection string in Key Vault
resource "azurerm_key_vault_secret" "service_bus_connection" {
  name         = "ServiceBusConnection"
  value        = azurerm_servicebus_namespace_authorization_rule.logic_apps.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  content_type = "application/x-connection-string"
  
  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    azurerm_role_assignment.keyvault_admin
  ]
  
  tags = local.common_tags
}

# Storage Account - Required for Logic Apps runtime
resource "azurerm_storage_account" "logic_apps" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  access_tier              = var.storage_account_access_tier
  
  # Security configuration
  https_traffic_only_enabled      = var.enable_https_only
  min_tls_version                 = var.storage_account_min_tls_version
  allow_nested_items_to_be_public = false
  
  # Network access configuration
  default_to_oauth_authentication = true
  
  # Enable blob versioning for better data protection
  blob_properties {
    versioning_enabled = true
    
    # Configure delete retention
    delete_retention_policy {
      days = var.backup_retention_days
    }
    
    # Configure container delete retention
    container_delete_retention_policy {
      days = var.backup_retention_days
    }
  }
  
  tags = local.common_tags
}

# Network access restrictions for Storage Account
resource "azurerm_storage_account_network_rules" "logic_apps" {
  storage_account_id = azurerm_storage_account.logic_apps.id
  
  default_action = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
  ip_rules       = var.allowed_ip_ranges
  bypass         = ["AzureServices"]
}

# App Service Plan - Hosting plan for Logic Apps
resource "azurerm_service_plan" "logic_apps" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = var.logic_app_plan_os_type
  sku_name            = var.logic_app_plan_sku
  
  tags = local.common_tags
}

# Logic Apps Workflow - Main orchestration service
resource "azurerm_logic_app_standard" "main" {
  name                       = local.logic_app_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  service_plan_id            = azurerm_service_plan.logic_apps.id
  storage_account_name       = azurerm_storage_account.logic_apps.name
  storage_account_access_key = azurerm_storage_account.logic_apps.primary_access_key
  
  # Application settings for Logic Apps
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "AzureWebJobsStorage"         = azurerm_storage_account.logic_apps.primary_connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.logic_apps.primary_connection_string
    "WEBSITE_CONTENTSHARE"        = lower(local.logic_app_name)
  }
  
  # Identity configuration for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Azure AD Application Registration - Service principal for automation
resource "azuread_application" "onboarding" {
  display_name     = var.ad_app_display_name
  sign_in_audience = var.ad_app_sign_in_audience
  
  # Configure API permissions for user management
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    
    resource_access {
      id   = "62a82d76-70ea-41e2-9197-370581804d09" # Group.ReadWrite.All
      type = "Role"
    }
    
    resource_access {
      id   = "19dbc75e-c2e2-444c-a770-ec69d8559fc7" # Directory.ReadWrite.All
      type = "Role"
    }
    
    resource_access {
      id   = "9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8" # Directory.Read.All
      type = "Role"
    }
  }
  
  # Configure web application properties
  web {
    implicit_grant {
      access_token_issuance_enabled = false
    }
  }
}

# Service Principal for the application
resource "azuread_service_principal" "onboarding" {
  application_id = azuread_application.onboarding.application_id
  
  # Automatically assign users and groups
  app_role_assignment_required = false
  
  tags = ["terraform", "user-onboarding", var.environment]
}

# Generate client secret for service principal
resource "azuread_application_password" "onboarding" {
  application_object_id = azuread_application.onboarding.object_id
  display_name          = "Terraform managed secret"
  end_date              = timeadd(timestamp(), "8760h") # 1 year from now
}

# Store application credentials in Key Vault
resource "azurerm_key_vault_secret" "app_client_id" {
  name         = "ApplicationClientId"
  value        = azuread_application.onboarding.application_id
  key_vault_id = azurerm_key_vault.main.id
  content_type = "text/plain"
  
  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    azurerm_role_assignment.keyvault_admin
  ]
  
  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "app_client_secret" {
  name         = "ApplicationClientSecret"
  value        = azuread_application_password.onboarding.value
  key_vault_id = azurerm_key_vault.main.id
  content_type = "text/plain"
  
  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    azurerm_role_assignment.keyvault_admin
  ]
  
  tags = local.common_tags
}

# Grant Logic Apps access to Key Vault
resource "azurerm_key_vault_access_policy" "logic_apps" {
  count = var.enable_rbac_authorization ? 0 : 1
  
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_logic_app_standard.main.identity[0].principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# RBAC role assignment for Logic Apps to access Key Vault secrets
resource "azurerm_role_assignment" "logic_apps_keyvault" {
  count = var.enable_rbac_authorization ? 1 : 0
  
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_logic_app_standard.main.identity[0].principal_id
}

# Grant Logic Apps access to Service Bus
resource "azurerm_role_assignment" "logic_apps_servicebus" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_logic_app_standard.main.identity[0].principal_id
}

# Log Analytics Workspace - Centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                = "log-${var.project_name}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Diagnostic Settings for Key Vault
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "diag-${azurerm_key_vault.main.name}"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  log {
    category = "AuditEvent"
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Diagnostic Settings for Service Bus
resource "azurerm_monitor_diagnostic_setting" "servicebus" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "diag-${azurerm_servicebus_namespace.main.name}"
  target_resource_id         = azurerm_servicebus_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  log {
    category = "OperationalLogs"
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Diagnostic Settings for Logic Apps
resource "azurerm_monitor_diagnostic_setting" "logicapp" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "diag-${azurerm_logic_app_standard.main.name}"
  target_resource_id         = azurerm_logic_app_standard.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  log {
    category = "FunctionAppLogs"
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    
    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}

# Application Insights - Application performance monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].id : null
  application_type    = "web"
  
  tags = local.common_tags
}

# Time-based resource for managing secret rotation
resource "time_rotating" "secret_rotation" {
  rotation_days = 90
}

# Auto-shutdown configuration for development environment
resource "azurerm_dev_test_global_vm_shutdown_schedule" "logic_apps" {
  count = var.auto_shutdown_enabled && var.environment == "dev" ? 1 : 0
  
  location              = azurerm_resource_group.main.location
  virtual_machine_id    = azurerm_service_plan.logic_apps.id
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = "UTC"
  
  notification_settings {
    enabled = false
  }
  
  tags = local.common_tags
}