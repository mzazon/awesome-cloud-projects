# Main Terraform configuration for Azure real-time collaborative applications
# This file creates all the infrastructure needed for a collaborative whiteboard application
# using Azure Communication Services and Azure Fluid Relay

# Get current Azure configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  # Create naming convention with optional prefix and suffix
  name_suffix = var.use_random_suffix ? random_string.suffix[0].result : ""
  name_prefix = var.resource_name_prefix != "" ? "${var.resource_name_prefix}-" : ""
  
  # Base name for all resources
  base_name = "${local.name_prefix}${var.project_name}"
  
  # Full name with suffix
  full_name = local.name_suffix != "" ? "${local.base_name}-${local.name_suffix}" : local.base_name
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project      = var.project_name
    DeployedBy   = "terraform"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Storage account name (must be globally unique, no hyphens)
  storage_name = replace("st${var.project_name}${local.name_suffix}", "-", "")
  
  # Key Vault name (must be globally unique)
  key_vault_name = "kv-${local.full_name}"
  
  # Function App name (must be globally unique)
  function_app_name = "func-${local.full_name}"
  
  # Resource group name
  resource_group_name = "rg-${local.full_name}"
}

# Create the main resource group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  
  tags = local.common_tags
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.full_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.app_insights_retention_days
  
  tags = local.common_tags
}

# Create Application Insights for monitoring and telemetry
resource "azurerm_application_insights" "main" {
  name                = "appi-${local.full_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.app_insights_type
  retention_in_days   = var.app_insights_retention_days
  
  tags = local.common_tags
}

# Create Azure Communication Services resource
resource "azurerm_communication_service" "main" {
  name                = "acs-${local.full_name}"
  resource_group_name = azurerm_resource_group.main.name
  data_location       = var.acs_data_location
  
  tags = local.common_tags
}

# Create Azure Fluid Relay service
resource "azurerm_fluid_relay_server" "main" {
  name                = "fluid-${local.full_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Configure Fluid Relay settings
  sku {
    name = var.fluid_relay_sku
  }
  
  tags = local.common_tags
}

# Create Storage Account for application data
resource "azurerm_storage_account" "main" {
  name                     = local.storage_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable security features
  enable_https_traffic_only      = true
  min_tls_version               = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob versioning and change feed for collaborative features
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Configure blob retention
    delete_retention_policy {
      days = 7
    }
    
    # Configure container delete retention
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Create storage containers for different types of data
resource "azurerm_storage_container" "main" {
  for_each = toset(var.storage_containers)
  
  name                  = each.key
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Create Key Vault for secure storage of secrets
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  # Configure Key Vault settings
  sku_name                    = var.key_vault_sku
  soft_delete_retention_days  = var.key_vault_soft_delete_retention
  purge_protection_enabled    = false
  enable_rbac_authorization   = true
  
  # Network access configuration
  network_acls {
    default_action = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = local.common_tags
}

# Create App Service Plan for Azure Functions
resource "azurerm_service_plan" "main" {
  name                = "sp-${local.full_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Use consumption plan for cost optimization
  os_type  = "Linux"
  sku_name = "Y1"
  
  tags = local.common_tags
}

# Create Azure Function App
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  # Configure storage settings
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Configure runtime settings
  site_config {
    always_on = false
    
    # Configure runtime stack
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # Configure CORS settings
    cors {
      allowed_origins = var.enable_cors_all_origins ? ["*"] : var.cors_allowed_origins
      support_credentials = false
    }
    
    # Enable Application Insights
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key              = azurerm_application_insights.main.instrumentation_key
  }
  
  # Configure application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"         = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"      = "~${var.function_app_functions_version}"
    "WEBSITE_NODE_DEFAULT_VERSION"     = var.function_app_runtime_version
    "WEBSITE_RUN_FROM_PACKAGE"         = "1"
    
    # Azure Communication Services settings (using Key Vault references)
    "ACS_CONNECTION_STRING" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=AcsConnectionString)"
    
    # Azure Fluid Relay settings (using Key Vault references)
    "FLUID_RELAY_KEY"       = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=FluidRelayKey)"
    "FLUID_ENDPOINT"        = azurerm_fluid_relay_server.main.orderer_endpoints[0]
    "FLUID_TENANT_ID"       = azurerm_fluid_relay_server.main.frs_tenant_id
    
    # Storage settings
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.main.primary_connection_string
    
    # Application Insights settings
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
  }
  
  # Configure HTTPS settings
  https_only = true
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_key_vault_secret.acs_connection_string,
    azurerm_key_vault_secret.fluid_relay_key
  ]
}

# Store Azure Communication Services connection string in Key Vault
resource "azurerm_key_vault_secret" "acs_connection_string" {
  name         = "AcsConnectionString"
  value        = azurerm_communication_service.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
  
  depends_on = [azurerm_role_assignment.key_vault_current_user]
}

# Store Azure Fluid Relay key in Key Vault
resource "azurerm_key_vault_secret" "fluid_relay_key" {
  name         = "FluidRelayKey"
  value        = azurerm_fluid_relay_server.main.primary_key
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
  
  depends_on = [azurerm_role_assignment.key_vault_current_user]
}

# Store storage connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "StorageConnectionString"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
  
  depends_on = [azurerm_role_assignment.key_vault_current_user]
}

# Grant current user Key Vault Secrets Officer role to create secrets
resource "azurerm_role_assignment" "key_vault_current_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant Function App access to Key Vault secrets
resource "azurerm_role_assignment" "key_vault_function_app" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Storage Account
resource "azurerm_role_assignment" "storage_function_app" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Application Insights
resource "azurerm_role_assignment" "app_insights_function_app" {
  scope                = azurerm_application_insights.main.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Create diagnostic settings for Azure Communication Services
resource "azurerm_monitor_diagnostic_setting" "acs" {
  name               = "diag-${azurerm_communication_service.main.name}"
  target_resource_id = azurerm_communication_service.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "AuthOperational"
  }
  
  enabled_log {
    category = "ChatOperational"
  }
  
  enabled_log {
    category = "SMSOperational"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name               = "diag-${azurerm_storage_account.main.name}"
  target_resource_id = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name               = "diag-${azurerm_linux_function_app.main.name}"
  target_resource_id = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic settings for Key Vault
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name               = "diag-${azurerm_key_vault.main.name}"
  target_resource_id = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
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

# Add a time delay to ensure resources are fully provisioned
resource "time_sleep" "wait_for_resources" {
  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_role_assignment.key_vault_function_app,
    azurerm_role_assignment.storage_function_app
  ]
  
  create_duration = "60s"
}