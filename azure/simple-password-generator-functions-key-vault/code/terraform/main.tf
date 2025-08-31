# Azure Password Generator Infrastructure with Functions and Key Vault
# This configuration creates a serverless password generator using Azure Functions and Key Vault
# with managed identity for secure, credential-free authentication

# Data Sources for Current Azure Context

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate Random Suffix for Unique Resource Names

# Generate a random suffix to ensure unique resource names across Azure
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed configurations
locals {
  # Generate unique resource names with random suffix
  random_suffix = lower(random_id.suffix.hex)
  
  # Resource naming convention: {project}-{component}-{environment}-{random}
  resource_group_name  = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.random_suffix}"
  key_vault_name      = "kv-${var.project_name}-${local.random_suffix}"
  storage_account_name = "st${replace(var.project_name, "-", "")}${local.random_suffix}"
  function_app_name   = "func-${var.project_name}-${var.environment}-${local.random_suffix}"
  app_service_plan_name = "asp-${var.project_name}-${var.environment}-${local.random_suffix}"
  app_insights_name   = "ai-${var.project_name}-${var.environment}-${local.random_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment     = var.environment
    Project        = var.project_name
    Purpose        = "password-generator"
    ManagedBy      = "terraform"
    CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
    Recipe         = "simple-password-generator-functions-key-vault"
  }, var.additional_tags)
}

# Resource Group - Container for all Azure resources

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Storage Account - Required for Azure Functions runtime

# Storage account for Function App runtime, triggers, and logs
resource "azurerm_storage_account" "function_storage" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  # Storage configuration for Function Apps
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication
  account_kind            = "StorageV2"
  
  # Security settings
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Blob properties for enhanced security
  blob_properties {
    # Enable versioning for better data protection
    versioning_enabled = true
    
    # Configure delete retention for blob recovery
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

# Key Vault - Secure storage for generated passwords

# Azure Key Vault for secure password storage with enterprise-grade security
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  # Key Vault configuration
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = var.key_vault_retention_days
  purge_protection_enabled   = var.enable_purge_protection
  
  # Security settings
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false
  enable_rbac_authorization      = true
  
  # Network access configuration (allow all for demo, restrict in production)
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# Application Insights - Monitoring and analytics for Function App

# Application Insights workspace for Function App monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = "law-${var.project_name}-${var.environment}-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  # Workspace configuration
  sku               = "PerGB2018"
  retention_in_days = 30
  
  tags = local.common_tags
}

# Application Insights component for application monitoring
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  # Application Insights configuration
  application_type                = var.application_insights_type
  workspace_id                   = azurerm_log_analytics_workspace.main[0].id
  internet_ingestion_enabled     = true
  internet_query_enabled         = true
  
  tags = local.common_tags
}

# App Service Plan - Hosting plan for Azure Functions

# Consumption plan for serverless Azure Functions with automatic scaling
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  # Consumption plan configuration (serverless)
  os_type  = "Linux"
  sku_name = "Y1"  # Dynamic consumption plan
  
  tags = local.common_tags
}

# Azure Function App - Serverless compute for password generation

# Function App with system-assigned managed identity for secure Key Vault access
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  # Storage configuration for Function App
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Function App configuration
  functions_extension_version = "~4"
  
  # Enable system-assigned managed identity for Key Vault access
  identity {
    type = "SystemAssigned"
  }
  
  # Site configuration
  site_config {
    # Runtime configuration
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # Security settings
    ftps_state               = "Disabled"
    http2_enabled           = true
    minimum_tls_version     = var.minimum_tls_version
    
    # CORS configuration for API access
    cors {
      allowed_origins     = var.allowed_origins
      support_credentials = false
    }
    
    # Application Insights configuration
    dynamic "application_insights_connection_string" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        value = azurerm_application_insights.main[0].connection_string
      }
    }
    
    dynamic "application_insights_key" {
      for_each = var.enable_application_insights ? [1] : []
      content {
        value = azurerm_application_insights.main[0].instrumentation_key
      }
    }
  }
  
  # Application settings for Function App
  app_settings = merge({
    # Key Vault URI for password storage
    "KEY_VAULT_URI" = azurerm_key_vault.main.vault_uri
    
    # Function runtime configuration
    "FUNCTIONS_WORKER_RUNTIME" = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION" = "~${var.function_app_runtime_version}"
    
    # Application Insights configuration (if enabled)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Additional settings
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
  }, var.function_app_settings)
  
  # Security settings
  https_only = var.enable_https_only
  
  tags = local.common_tags
  
  # Ensure dependencies are created first
  depends_on = [
    azurerm_storage_account.function_storage,
    azurerm_key_vault.main,
    azurerm_service_plan.main
  ]
}

# Role Assignments - RBAC permissions for managed identity

# Grant Key Vault Secrets Officer role to Function App managed identity
# This allows the Function App to create, read, and manage secrets in Key Vault
resource "azurerm_role_assignment" "function_keyvault_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [
    azurerm_linux_function_app.main,
    azurerm_key_vault.main
  ]
}

# Optional: Additional Key Vault access policies for external users/applications
resource "azurerm_key_vault_access_policy" "additional" {
  count = length(var.key_vault_access_policies)
  
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = var.key_vault_access_policies[count.index].tenant_id
  object_id    = var.key_vault_access_policies[count.index].object_id
  
  secret_permissions      = var.key_vault_access_policies[count.index].secret_permissions
  key_permissions        = var.key_vault_access_policies[count.index].key_permissions
  certificate_permissions = var.key_vault_access_policies[count.index].certificate_permissions
}

# Function Code Deployment (placeholder for actual deployment)

# Note: This Terraform configuration creates the infrastructure only.
# Function code deployment should be handled separately using:
# 1. Azure Functions Core Tools: func azure functionapp publish
# 2. GitHub Actions with azure/functions-action
# 3. Azure DevOps pipelines
# 4. ZIP deployment via Azure CLI

# The Function App is configured and ready to receive code deployment
# with proper managed identity and Key Vault access configured.