# SMS Compliance Automation with Communication Services
# This Terraform configuration deploys Azure Communication Services with Azure Functions
# for automated SMS compliance management including opt-out processing

# Configure Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-sms-compliance-${random_id.suffix.hex}"
  location = var.location

  tags = merge(var.common_tags, {
    Purpose     = "SMS Compliance Automation"
    Environment = "Demo"
  })
}

# Create Azure Communication Services resource
# This provides SMS services with the new Opt-Out Management API
resource "azurerm_communication_service" "main" {
  name                = "sms-comm-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  data_location       = var.data_location

  tags = var.common_tags
}

# Create Storage Account for Function App runtime and audit logs
resource "azurerm_storage_account" "main" {
  name                     = "smsstorage${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"

  # Enable secure transfer and disable public access
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  min_tls_version          = "TLS1_2"

  # Configure blob properties for security
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
  }

  tags = var.common_tags
}

# Create Storage Table for compliance audit logs
resource "azurerm_storage_table" "audit" {
  name                 = "optoutaudit"
  storage_account_name = azurerm_storage_account.main.name
}

# Create Application Insights for monitoring Function App
resource "azurerm_application_insights" "main" {
  name                = "sms-compliance-insights-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_days

  tags = var.common_tags
}

# Create App Service Plan for Function App (Consumption Plan)
resource "azurerm_service_plan" "main" {
  name                = "sms-compliance-plan-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption (Serverless) Plan

  tags = var.common_tags
}

# Create Function App for SMS compliance automation
resource "azurerm_linux_function_app" "main" {
  name                = "sms-compliance-func-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id           = azurerm_service_plan.main.id

  # Enable system-assigned managed identity for secure access
  identity {
    type = "SystemAssigned"
  }

  # Configure Function App settings
  site_config {
    application_stack {
      node_version = "20"
    }

    # Security configurations
    ftps_state              = "Disabled"
    http2_enabled          = true
    minimum_tls_version    = "1.2"
    use_32_bit_worker      = false

    # CORS configuration for web integration
    cors {
      allowed_origins = var.allowed_cors_origins
      support_credentials = true
    }
  }

  # Application settings for Communication Services integration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"              = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"          = "~20"
    "FUNCTIONS_EXTENSION_VERSION"           = "~4"
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Communication Services connection string
    "CommunicationServicesConnectionString" = azurerm_communication_service.main.primary_connection_string
    
    # Storage connection for audit logs
    "StorageConnectionString" = azurerm_storage_account.main.primary_connection_string
    
    # Compliance configuration
    "COMPLIANCE_AUDIT_TABLE" = azurerm_storage_table.audit.name
  }

  # Lifecycle management
  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_ENABLE_SYNC_UPDATE_SITE"],
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
    ]
  }

  tags = var.common_tags
}

# Create Storage Container for function deployments
resource "azurerm_storage_container" "deployments" {
  name                  = "function-deployments"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create Key Vault for storing sensitive configuration (optional)
resource "azurerm_key_vault" "main" {
  count = var.enable_key_vault ? 1 : 0

  name                = "sms-kv-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Security configurations
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  purge_protection_enabled       = false
  soft_delete_retention_days     = 7

  # Network access control
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = var.common_tags
}

# Grant Function App access to Key Vault
resource "azurerm_key_vault_access_policy" "function_app" {
  count = var.enable_key_vault ? 1 : 0

  key_vault_id = azurerm_key_vault.main[0].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_function_app.main.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}

# Store Communication Services connection string in Key Vault
resource "azurerm_key_vault_secret" "comm_connection_string" {
  count = var.enable_key_vault ? 1 : 0

  name         = "CommunicationServicesConnectionString"
  value        = azurerm_communication_service.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main[0].id

  depends_on = [azurerm_key_vault_access_policy.function_app]

  tags = var.common_tags
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Log Analytics Workspace for enhanced monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_log_analytics ? 1 : 0

  name                = "sms-compliance-logs-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days

  tags = var.common_tags
}

# Configure diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count = var.enable_log_analytics ? 1 : 0

  name                       = "function-app-diagnostics"
  target_resource_id         = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "FunctionAppLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Configure diagnostic settings for Communication Services
resource "azurerm_monitor_diagnostic_setting" "communication_service" {
  count = var.enable_log_analytics ? 1 : 0

  name                       = "communication-service-diagnostics"
  target_resource_id         = azurerm_communication_service.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "SMSOperational"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}