# Main Terraform Configuration for Azure Accessible AI-Powered Customer Service Bot
# This file creates the complete infrastructure for an accessible customer service bot
# using Azure Immersive Reader and Bot Framework

# Data sources for current Azure context
data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and tagging
locals {
  # Generate unique suffix based on configuration
  suffix = var.use_random_suffix ? random_string.suffix.result : ""
  
  # Build resource name prefix
  name_prefix = var.resource_name_prefix != "" ? "${var.resource_name_prefix}-" : ""
  
  # Common resource naming pattern
  resource_names = {
    immersive_reader    = "${local.name_prefix}immersive-reader${local.suffix != "" ? "-${local.suffix}" : ""}"
    luis_authoring      = "${local.name_prefix}luis-authoring${local.suffix != "" ? "-${local.suffix}" : ""}"
    luis_runtime        = "${local.name_prefix}luis-runtime${local.suffix != "" ? "-${local.suffix}" : ""}"
    key_vault          = "${local.name_prefix}kv-bot${local.suffix != "" ? "-${local.suffix}" : ""}"
    storage_account    = "${local.name_prefix}stbot${local.suffix}"
    app_service_plan   = "${local.name_prefix}asp-accessible-bot${local.suffix != "" ? "-${local.suffix}" : ""}"
    app_service        = "${local.name_prefix}app-accessible-bot${local.suffix != "" ? "-${local.suffix}" : ""}"
    application_insights = "${local.name_prefix}ai-accessible-bot${local.suffix != "" ? "-${local.suffix}" : ""}"
    bot_service        = "${local.name_prefix}${var.bot_name}${local.suffix != "" ? "-${local.suffix}" : ""}"
  }
  
  # Merge common tags with additional tags
  tags = merge(var.common_tags, var.additional_tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# Create Azure Immersive Reader Cognitive Service
# This service provides reading assistance features for accessibility
resource "azurerm_cognitive_service" "immersive_reader" {
  name                = local.resource_names.immersive_reader
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "ImmersiveReader"
  sku_name            = var.cognitive_services_sku
  
  # Custom subdomain is required for Immersive Reader
  custom_subdomain_name = local.resource_names.immersive_reader
  
  # Enable public network access based on configuration
  public_network_access_enabled = var.enable_public_network_access
  
  tags = merge(local.tags, {
    Service = "immersive-reader"
    Purpose = "accessibility"
  })
}

# Create LUIS Authoring Cognitive Service
# This service handles natural language understanding for bot conversations
resource "azurerm_cognitive_service" "luis_authoring" {
  name                = local.resource_names.luis_authoring
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "LUIS.Authoring"
  sku_name            = var.luis_authoring_sku
  
  # Enable public network access based on configuration
  public_network_access_enabled = var.enable_public_network_access
  
  tags = merge(local.tags, {
    Service = "luis-authoring"
    Purpose = "language-understanding"
  })
}

# Create LUIS Runtime Cognitive Service
# This service provides runtime prediction capabilities for LUIS applications
resource "azurerm_cognitive_service" "luis_runtime" {
  name                = local.resource_names.luis_runtime
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "LUIS"
  sku_name            = var.cognitive_services_sku
  
  # Enable public network access based on configuration
  public_network_access_enabled = var.enable_public_network_access
  
  tags = merge(local.tags, {
    Service = "luis-runtime"
    Purpose = "language-understanding"
  })
}

# Create Key Vault for secure credential storage
# This provides centralized, secure storage for API keys and connection strings
resource "azurerm_key_vault" "main" {
  name                = local.resource_names.key_vault
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  sku_name = var.key_vault_sku
  
  # Soft delete configuration
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = false
  
  # Access policy configuration
  enable_rbac_authorization = var.enable_rbac_authorization
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_network_access
  
  # IP access rules if specified
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_addresses) > 0 ? [1] : []
    content {
      default_action = "Deny"
      bypass         = "AzureServices"
      ip_rules       = var.allowed_ip_addresses
    }
  }
  
  tags = merge(local.tags, {
    Service = "key-vault"
    Purpose = "secure-configuration"
  })
}

# Key Vault access policy for current service principal
resource "azurerm_key_vault_access_policy" "current" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
}

# Store Immersive Reader credentials in Key Vault
resource "azurerm_key_vault_secret" "immersive_reader_key" {
  depends_on   = [azurerm_key_vault_access_policy.current]
  name         = "ImmersiveReaderKey"
  value        = azurerm_cognitive_service.immersive_reader.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(local.tags, {
    Service = "immersive-reader"
    Type    = "api-key"
  })
}

resource "azurerm_key_vault_secret" "immersive_reader_endpoint" {
  depends_on   = [azurerm_key_vault_access_policy.current]
  name         = "ImmersiveReaderEndpoint"
  value        = azurerm_cognitive_service.immersive_reader.endpoint
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(local.tags, {
    Service = "immersive-reader"
    Type    = "endpoint"
  })
}

# Store LUIS credentials in Key Vault
resource "azurerm_key_vault_secret" "luis_authoring_key" {
  depends_on   = [azurerm_key_vault_access_policy.current]
  name         = "LuisAuthoringKey"
  value        = azurerm_cognitive_service.luis_authoring.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(local.tags, {
    Service = "luis-authoring"
    Type    = "api-key"
  })
}

resource "azurerm_key_vault_secret" "luis_authoring_endpoint" {
  depends_on   = [azurerm_key_vault_access_policy.current]
  name         = "LuisAuthoringEndpoint"
  value        = azurerm_cognitive_service.luis_authoring.endpoint
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(local.tags, {
    Service = "luis-authoring"
    Type    = "endpoint"
  })
}

resource "azurerm_key_vault_secret" "luis_runtime_key" {
  depends_on   = [azurerm_key_vault_access_policy.current]
  name         = "LuisRuntimeKey"
  value        = azurerm_cognitive_service.luis_runtime.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(local.tags, {
    Service = "luis-runtime"
    Type    = "api-key"
  })
}

resource "azurerm_key_vault_secret" "luis_runtime_endpoint" {
  depends_on   = [azurerm_key_vault_access_policy.current]
  name         = "LuisRuntimeEndpoint"
  value        = azurerm_cognitive_service.luis_runtime.endpoint
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(local.tags, {
    Service = "luis-runtime"
    Type    = "endpoint"
  })
}

# Create Storage Account for bot state management
# This provides persistent storage for conversation state and user preferences
resource "azurerm_storage_account" "main" {
  name                     = replace(local.resource_names.storage_account, "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Security configuration
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob encryption
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = merge(local.tags, {
    Service = "storage"
    Purpose = "bot-state"
  })
}

# Store storage connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  depends_on   = [azurerm_key_vault_access_policy.current]
  name         = "StorageConnectionString"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(local.tags, {
    Service = "storage"
    Type    = "connection-string"
  })
}

# Create Application Insights for monitoring and telemetry
resource "azurerm_application_insights" "main" {
  name                = local.resource_names.application_insights
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = var.application_insights_type
  retention_in_days   = var.application_insights_retention_days
  
  tags = merge(local.tags, {
    Service = "monitoring"
    Purpose = "telemetry"
  })
}

# Create App Service Plan for hosting the bot application
resource "azurerm_service_plan" "main" {
  name                = local.resource_names.app_service_plan
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  os_type  = var.app_service_plan_kind
  sku_name = var.app_service_plan_sku
  
  tags = merge(local.tags, {
    Service = "app-service-plan"
    Purpose = "bot-hosting"
  })
}

# Create App Service for the bot application
resource "azurerm_linux_web_app" "main" {
  count               = var.app_service_plan_kind == "Linux" ? 1 : 0
  name                = local.resource_names.app_service
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  # Enable managed identity for Key Vault access
  identity {
    type = "SystemAssigned"
  }
  
  site_config {
    always_on = var.app_service_plan_sku != "F1" && var.app_service_plan_sku != "D1"
    
    application_stack {
      node_version = var.node_version
    }
    
    # Enable detailed error messages for debugging
    detailed_error_logging_enabled = true
    
    # Configure CORS for bot framework
    cors {
      allowed_origins = ["*"]
      support_credentials = false
    }
  }
  
  # Application settings with Key Vault references
  app_settings = {
    "NODE_ENV"                           = "production"
    "WEBSITE_NODE_DEFAULT_VERSION"       = "~${split("-", var.node_version)[0]}"
    "APPINSIGHTS_INSTRUMENTATIONKEY"     = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Bot Framework settings
    "MicrosoftAppId"                     = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=BotAppId)"
    "MicrosoftAppPassword"               = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=BotAppPassword)"
    
    # Cognitive Services settings
    "ImmersiveReaderKey"                 = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=ImmersiveReaderKey)"
    "ImmersiveReaderEndpoint"            = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=ImmersiveReaderEndpoint)"
    "LuisAuthoringKey"                   = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=LuisAuthoringKey)"
    "LuisAuthoringEndpoint"              = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=LuisAuthoringEndpoint)"
    "LuisRuntimeKey"                     = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=LuisRuntimeKey)"
    "LuisRuntimeEndpoint"                = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=LuisRuntimeEndpoint)"
    
    # Storage settings
    "StorageConnectionString"            = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=StorageConnectionString)"
    
    # Bot-specific settings
    "BotId"                             = local.resource_names.bot_service
    "BotName"                           = var.bot_display_name
    "BotDescription"                    = var.bot_description
  }
  
  tags = merge(local.tags, {
    Service = "web-app"
    Purpose = "bot-application"
  })
}

# Create Windows App Service if specified
resource "azurerm_windows_web_app" "main" {
  count               = var.app_service_plan_kind == "Windows" ? 1 : 0
  name                = local.resource_names.app_service
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  # Enable managed identity for Key Vault access
  identity {
    type = "SystemAssigned"
  }
  
  site_config {
    always_on = var.app_service_plan_sku != "F1" && var.app_service_plan_sku != "D1"
    
    application_stack {
      node_version = var.node_version
    }
    
    # Enable detailed error messages for debugging
    detailed_error_logging_enabled = true
    
    # Configure CORS for bot framework
    cors {
      allowed_origins = ["*"]
      support_credentials = false
    }
  }
  
  # Application settings with Key Vault references (same as Linux)
  app_settings = {
    "NODE_ENV"                           = "production"
    "WEBSITE_NODE_DEFAULT_VERSION"       = "~${split("-", var.node_version)[0]}"
    "APPINSIGHTS_INSTRUMENTATIONKEY"     = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Bot Framework settings
    "MicrosoftAppId"                     = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=BotAppId)"
    "MicrosoftAppPassword"               = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=BotAppPassword)"
    
    # Cognitive Services settings
    "ImmersiveReaderKey"                 = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=ImmersiveReaderKey)"
    "ImmersiveReaderEndpoint"            = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=ImmersiveReaderEndpoint)"
    "LuisAuthoringKey"                   = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=LuisAuthoringKey)"
    "LuisAuthoringEndpoint"              = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=LuisAuthoringEndpoint)"
    "LuisRuntimeKey"                     = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=LuisRuntimeKey)"
    "LuisRuntimeEndpoint"                = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=LuisRuntimeEndpoint)"
    
    # Storage settings
    "StorageConnectionString"            = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=StorageConnectionString)"
    
    # Bot-specific settings
    "BotId"                             = local.resource_names.bot_service
    "BotName"                           = var.bot_display_name
    "BotDescription"                    = var.bot_description
  }
  
  tags = merge(local.tags, {
    Service = "web-app"
    Purpose = "bot-application"
  })
}

# Get the appropriate app service based on OS type
locals {
  app_service = var.app_service_plan_kind == "Linux" ? azurerm_linux_web_app.main[0] : azurerm_windows_web_app.main[0]
}

# Key Vault access policy for App Service managed identity
resource "azurerm_key_vault_access_policy" "app_service" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = local.app_service.identity[0].tenant_id
  object_id    = local.app_service.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
}

# Create Azure AD application for the bot
resource "azuread_application" "bot" {
  display_name = var.bot_display_name
  owners       = [data.azuread_client_config.current.object_id]
  
  # Required resource access for Bot Framework
  required_resource_access {
    resource_app_id = "00000002-0000-0000-c000-000000000000" # Microsoft Graph
    
    resource_access {
      id   = "311a71cc-e848-46a1-bdf8-97ff7156d8e6" # User.Read
      type = "Scope"
    }
  }
  
  # Enable implicit flow for web authentication
  web {
    implicit_grant {
      access_token_issuance_enabled = true
      id_token_issuance_enabled     = true
    }
  }
  
  tags = [
    "bot-framework",
    "accessible-customer-service"
  ]
}

# Create service principal for the bot application
resource "azuread_service_principal" "bot" {
  application_id = azuread_application.bot.application_id
  owners         = [data.azuread_client_config.current.object_id]
  
  tags = [
    "bot-framework",
    "accessible-customer-service"
  ]
}

# Create client secret for the bot application
resource "azuread_application_password" "bot" {
  application_object_id = azuread_application.bot.object_id
  display_name          = "Bot Framework Secret"
  
  # Secret expires in 2 years
  end_date_relative = "17520h" # 2 years in hours
}

# Store bot credentials in Key Vault
resource "azurerm_key_vault_secret" "bot_app_id" {
  depends_on   = [azurerm_key_vault_access_policy.current]
  name         = "BotAppId"
  value        = azuread_application.bot.application_id
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(local.tags, {
    Service = "bot-framework"
    Type    = "app-id"
  })
}

resource "azurerm_key_vault_secret" "bot_app_password" {
  depends_on   = [azurerm_key_vault_access_policy.current]
  name         = "BotAppPassword"
  value        = azuread_application_password.bot.value
  key_vault_id = azurerm_key_vault.main.id
  
  tags = merge(local.tags, {
    Service = "bot-framework"
    Type    = "app-password"
  })
}

# Create Azure Bot Service registration
resource "azurerm_bot_service_azure_bot" "main" {
  name                = local.resource_names.bot_service
  resource_group_name = azurerm_resource_group.main.name
  location            = "global" # Bot service is global
  
  microsoft_app_id = azuread_application.bot.application_id
  sku              = "F0" # Free tier for development
  
  # Bot endpoint URL pointing to the App Service
  endpoint = "https://${local.app_service.default_hostname}/api/messages"
  
  # Developer information
  developer_app_insights_key                = azurerm_application_insights.main.instrumentation_key
  developer_app_insights_api_key            = null
  developer_app_insights_application_id     = azurerm_application_insights.main.app_id
  
  tags = merge(local.tags, {
    Service = "bot-framework"
    Purpose = "bot-registration"
  })
}

# Create Web Chat channel for the bot
resource "azurerm_bot_channel_web_chat" "main" {
  bot_name            = azurerm_bot_service_azure_bot.main.name
  location            = azurerm_bot_service_azure_bot.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Web Chat channel configuration
  site_names = ["Default Site"]
}

# Optional: Create diagnostic settings for monitoring
resource "azurerm_monitor_diagnostic_setting" "app_service" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "app-service-diagnostics"
  target_resource_id = local.app_service.id
  storage_account_id = azurerm_storage_account.main.id
  
  enabled_log {
    category = "AppServiceHTTPLogs"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "AppServiceConsoleLogs"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  enabled_log {
    category = "AppServiceAppLogs"
    
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

# Optional: Create action group for monitoring alerts
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "bot-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "bot-alerts"
  
  tags = merge(local.tags, {
    Service = "monitoring"
    Purpose = "alerts"
  })
}

# Optional: Create metric alert for high error rate
resource "azurerm_monitor_metric_alert" "high_error_rate" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "bot-high-error-rate"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [local.app_service.id]
  description         = "Alert when bot error rate is high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = merge(local.tags, {
    Service = "monitoring"
    Purpose = "error-alerting"
  })
}