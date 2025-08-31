# Main Terraform configuration for Azure Key Vault and App Service secrets management
# This infrastructure demonstrates secure secrets management using Azure Key Vault
# with App Service managed identities for passwordless authentication

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Get current Azure client configuration for RBAC assignments
data "azurerm_client_config" "current" {}

# Create Resource Group to contain all resources
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location = var.location
  tags     = var.tags
}

# Create Azure Key Vault for secure secrets storage
# Key Vault provides enterprise-grade security with HSM protection,
# detailed audit logging, and fine-grained access control
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  # Key Vault configuration
  sku_name                        = var.key_vault_sku
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  
  # Security settings
  purge_protection_enabled      = var.purge_protection_enabled
  soft_delete_retention_days    = var.soft_delete_retention_days
  enable_rbac_authorization     = var.enable_rbac_authorization
  
  # Network access configuration (allow access from all networks for demo)
  public_network_access_enabled = true
  
  tags = var.tags
}

# Assign Key Vault Secrets Officer role to current user for secret management
# This allows the deploying user to create and manage secrets in the vault
resource "azurerm_role_assignment" "current_user_secrets_officer" {
  count = var.enable_rbac_authorization ? 1 : 0
  
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Wait for role assignment propagation before creating secrets
resource "time_sleep" "rbac_propagation" {
  depends_on = [azurerm_role_assignment.current_user_secrets_officer]
  
  create_duration = "30s"
}

# Store sample database connection string in Key Vault
# This represents a typical application secret that would normally be hardcoded
resource "azurerm_key_vault_secret" "database_connection" {
  name         = "DatabaseConnection"
  value        = var.database_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  # Content type helps identify the type of secret
  content_type = "text/plain"
  
  tags = merge(var.tags, {
    SecretType = "database-connection"
  })
  
  depends_on = [time_sleep.rbac_propagation]
}

# Store sample external API key in Key Vault
# This demonstrates how API keys and service credentials can be managed centrally
resource "azurerm_key_vault_secret" "external_api_key" {
  name         = "ExternalApiKey"
  value        = var.external_api_key
  key_vault_id = azurerm_key_vault.main.id
  
  # Content type helps identify the type of secret
  content_type = "text/plain"
  
  tags = merge(var.tags, {
    SecretType = "api-key"
  })
  
  depends_on = [time_sleep.rbac_propagation]
}

# Create App Service Plan to host the web application
# The service plan defines compute resources and scaling capabilities
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Linux-based hosting for Node.js application
  os_type  = "Linux"
  sku_name = "${var.app_service_sku.tier}_${var.app_service_sku.size}"
  
  tags = var.tags
}

# Create Linux Web App with Node.js runtime
# This web application will demonstrate Key Vault integration through managed identity
resource "azurerm_linux_web_app" "main" {
  name                = "webapp-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  # Enable HTTPS only for security
  https_only = true
  
  # Application configuration
  site_config {
    # Node.js runtime configuration
    application_stack {
      node_version = var.node_version
    }
    
    # Security headers
    always_on = var.app_service_sku.tier != "Free" && var.app_service_sku.tier != "Shared"
    
    # Enable detailed error messages for debugging (disable in production)
    detailed_error_logging_enabled = true
    http_logging_enabled           = true
  }
  
  # Configure Key Vault references as application settings
  # These settings use special syntax to retrieve values from Key Vault at runtime
  app_settings = {
    # Key Vault reference syntax: @Microsoft.KeyVault(VaultName=vault-name;SecretName=secret-name)
    "DATABASE_CONNECTION" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=${azurerm_key_vault_secret.database_connection.name})"
    "API_KEY"            = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=${azurerm_key_vault_secret.external_api_key.name})"
    
    # Standard Node.js configuration
    "WEBSITE_NODE_DEFAULT_VERSION" = "~${var.node_version}"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
  }
  
  # Enable system-assigned managed identity
  # This creates an Azure AD identity tied to the web app lifecycle
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
  
  # Ensure secrets exist before creating the web app
  depends_on = [
    azurerm_key_vault_secret.database_connection,
    azurerm_key_vault_secret.external_api_key
  ]
}

# Grant Key Vault Secrets User role to the web app's managed identity
# This enables the web application to read secrets from Key Vault using RBAC
resource "azurerm_role_assignment" "webapp_secrets_user" {
  count = var.enable_rbac_authorization ? 1 : 0
  
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Alternative: Key Vault Access Policy (used when RBAC is disabled)
# This provides backwards compatibility with access policy-based authorization
resource "azurerm_key_vault_access_policy" "webapp_access" {
  count = var.enable_rbac_authorization ? 0 : 1
  
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_web_app.main.identity[0].principal_id
  
  # Minimal permissions for reading secrets only
  secret_permissions = [
    "Get",
  ]
}

# Wait for role assignment propagation before completing deployment
resource "time_sleep" "webapp_rbac_propagation" {
  depends_on = [
    azurerm_role_assignment.webapp_secrets_user,
    azurerm_key_vault_access_policy.webapp_access
  ]
  
  create_duration = "30s"
}