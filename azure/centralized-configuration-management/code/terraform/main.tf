# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current client configuration for tenant ID and object ID
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    Environment = var.environment
    Purpose     = var.purpose
    Recipe      = "config-management"
  })
}

# Create Azure App Configuration store
resource "azurerm_app_configuration" "main" {
  name                = "${var.app_config_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.app_config_sku

  tags = merge(var.tags, {
    Environment = var.environment
    Purpose     = "configuration"
  })
}

# Create Azure Key Vault
resource "azurerm_key_vault" "main" {
  name                = "${var.key_vault_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku

  # Enable soft delete and purge protection
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = false # Set to true for production workloads

  # Network access rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Purpose     = "secrets"
  })
}

# Grant current user access to Key Vault
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
}

# Create App Service Plan
resource "azurerm_service_plan" "main" {
  name                = "${var.app_service_plan_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku

  tags = merge(var.tags, {
    Environment = var.environment
    Purpose     = "hosting"
  })
}

# Create Web App
resource "azurerm_linux_web_app" "main" {
  name                = "${var.web_app_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id

  site_config {
    application_stack {
      node_version = var.node_version
    }
  }

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Purpose     = "application"
  })
}

# Role assignment for App Configuration Data Reader
resource "azurerm_role_assignment" "app_config_reader" {
  scope                = azurerm_app_configuration.main.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_web_app.main]
}

# Access policy for Key Vault secrets
resource "azurerm_key_vault_access_policy" "web_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_web_app.main.identity[0].principal_id

  secret_permissions = [
    "Get", "List"
  ]

  depends_on = [azurerm_linux_web_app.main]
}

# Add application settings to App Configuration
resource "azurerm_app_configuration_key" "app_settings" {
  for_each = var.app_settings

  configuration_store_id = azurerm_app_configuration.main.id
  key                    = each.key
  value                  = each.value.value
  label                  = each.value.label

  depends_on = [azurerm_role_assignment.app_config_reader]
}

# Add feature flags to App Configuration
resource "azurerm_app_configuration_feature" "feature_flags" {
  for_each = var.feature_flags

  configuration_store_id = azurerm_app_configuration.main.id
  name                   = each.key
  enabled                = each.value.enabled
  label                  = each.value.label

  depends_on = [azurerm_role_assignment.app_config_reader]
}

# Add secrets to Key Vault
resource "azurerm_key_vault_secret" "secrets" {
  for_each = var.key_vault_secrets

  name         = each.key
  value        = each.value.value
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# Configure Web App settings with App Configuration endpoint and Key Vault references
resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.main.id

  site_config {
    application_stack {
      node_version = var.node_version
    }
  }

  app_settings = {
    "AZURE_APP_CONFIG_ENDPOINT" = azurerm_app_configuration.main.endpoint
    "DATABASE_CONNECTION"       = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=DatabaseConnection)"
    "API_KEY"                   = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=ApiKey)"
  }

  depends_on = [
    azurerm_key_vault_access_policy.web_app,
    azurerm_key_vault_secret.secrets
  ]
}

# Configure Web App settings for production slot
resource "azurerm_linux_web_app" "main_with_settings" {
  name                = azurerm_linux_web_app.main.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id

  site_config {
    application_stack {
      node_version = var.node_version
    }
  }

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  # Configure application settings
  app_settings = {
    "AZURE_APP_CONFIG_ENDPOINT" = azurerm_app_configuration.main.endpoint
    "DATABASE_CONNECTION"       = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=DatabaseConnection)"
    "API_KEY"                   = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=ApiKey)"
    "WEBSITES_PORT"             = "3000"
    "NODE_ENV"                  = "production"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Purpose     = "application"
  })

  depends_on = [
    azurerm_key_vault_access_policy.web_app,
    azurerm_key_vault_secret.secrets
  ]

  lifecycle {
    replace_triggered_by = [azurerm_linux_web_app.main]
  }
}

# Application Insights for monitoring (optional but recommended)
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.web_app_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "Node.JS"

  tags = merge(var.tags, {
    Environment = var.environment
    Purpose     = "monitoring"
  })
}

# Add Application Insights connection string to Web App
resource "azurerm_linux_web_app" "main_with_insights" {
  name                = azurerm_linux_web_app.main.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id

  site_config {
    application_stack {
      node_version = var.node_version
    }
  }

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  # Configure application settings including Application Insights
  app_settings = {
    "AZURE_APP_CONFIG_ENDPOINT"              = azurerm_app_configuration.main.endpoint
    "DATABASE_CONNECTION"                    = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=DatabaseConnection)"
    "API_KEY"                                = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=ApiKey)"
    "WEBSITES_PORT"                          = "3000"
    "NODE_ENV"                               = "production"
    "APPINSIGHTS_INSTRUMENTATIONKEY"         = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"  = azurerm_application_insights.main.connection_string
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Purpose     = "application"
  })

  depends_on = [
    azurerm_key_vault_access_policy.web_app,
    azurerm_key_vault_secret.secrets,
    azurerm_application_insights.main
  ]

  lifecycle {
    replace_triggered_by = [azurerm_linux_web_app.main_with_settings]
  }
}