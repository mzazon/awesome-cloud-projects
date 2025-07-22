# Main Terraform configuration for Azure Edge-Based Healthcare Analytics
# This configuration deploys Azure SQL Edge, Azure Health Data Services, IoT Hub, and supporting services

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming
locals {
  resource_suffix    = random_id.suffix.hex
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${local.resource_suffix}"
  
  # Naming convention for all resources
  names = {
    iot_hub                = "iot-${var.project_name}-${local.resource_suffix}"
    health_workspace       = "ahds-${var.project_name}-${local.resource_suffix}"
    fhir_service          = "fhir-${var.project_name}-${local.resource_suffix}"
    function_app          = "func-${var.project_name}-${local.resource_suffix}"
    storage_account       = "st${var.project_name}${local.resource_suffix}"
    log_analytics         = "law-${var.project_name}-${local.resource_suffix}"
    app_insights          = "ai-${var.project_name}-${local.resource_suffix}"
    key_vault            = "kv-${var.project_name}-${local.resource_suffix}"
    app_service_plan     = "asp-${var.project_name}-${local.resource_suffix}"
  }

  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment      = var.environment
    ManagedBy       = "Terraform"
    LastModified    = timestamp()
    ResourceSuffix  = local.resource_suffix
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace (created first as other services depend on it)
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.names.log_analytics
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Application Insights for Function App monitoring
resource "azurerm_application_insights" "main" {
  name                = local.names.app_insights
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.common_tags
}

# Storage Account for Function App
resource "azurerm_storage_account" "main" {
  name                     = local.names.storage_account
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  
  # Enable advanced threat protection for healthcare compliance
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

# Key Vault for storing sensitive configuration
resource "azurerm_key_vault" "main" {
  name                = local.names.key_vault
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Enable for healthcare compliance
  enable_rbac_authorization = true
  purge_protection_enabled  = false  # Set to true for production
  soft_delete_retention_days = 7     # Minimum for healthcare scenarios
  
  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"  # Restrict to specific networks in production
  }

  tags = local.common_tags
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# IoT Hub for device management and data ingestion
resource "azurerm_iothub" "main" {
  name                = local.names.iot_hub
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku {
    name     = var.iot_hub_sku
    capacity = "1"
  }

  # Configure message retention and partitions for healthcare data
  event_hub_partition_count   = var.iot_hub_partition_count
  event_hub_retention_in_days = var.iot_hub_retention_days

  # Enable file upload for large medical files (images, reports)
  file_upload {
    connection_string  = azurerm_storage_account.main.primary_blob_connection_string
    container_name     = azurerm_storage_container.uploads.name
    default_ttl        = "PT1H"
    max_delivery_count = 10
  }

  tags = local.common_tags
}

# Storage container for IoT Hub file uploads
resource "azurerm_storage_container" "uploads" {
  name                  = "iothub-uploads"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# IoT Edge Device Identity
resource "azurerm_iothub_device" "edge_device" {
  name    = var.edge_device_id
  iothub_id = azurerm_iothub.main.id

  # Enable edge capabilities and authentication
  edge_enabled = true
  auth_method  = "shared_private_key"

  # Generate primary and secondary keys
  primary_key   = base64encode(random_id.primary_key.hex)
  secondary_key = base64encode(random_id.secondary_key.hex)
}

# Random keys for IoT device authentication
resource "random_id" "primary_key" {
  byte_length = 32
}

resource "random_id" "secondary_key" {
  byte_length = 32
}

# Store SQL Edge password in Key Vault
resource "azurerm_key_vault_secret" "sql_edge_password" {
  name         = "sql-edge-sa-password"
  value        = var.sql_edge_password
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

# Azure Health Data Services Workspace
resource "azurerm_healthcare_workspace" "main" {
  name                = local.names.health_workspace
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# FHIR Service for healthcare data compliance
resource "azurerm_healthcare_fhir_service" "main" {
  name                = local.names.fhir_service
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_healthcare_workspace.main.id
  kind                = "fhir-R4"

  # Configure authentication for FHIR service
  authentication {
    authority = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}"
    audience  = "https://azurehealthcareapis.com"
  }

  # CORS configuration for web applications
  cors {
    allowed_origins     = ["*"]  # Restrict to specific origins in production
    allowed_headers     = ["*"]
    allowed_methods     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    max_age_in_seconds  = 86400
    credentials_allowed = false
  }

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# App Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = local.names.app_service_plan
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_sku
  tags                = local.common_tags
}

# Function App for alert processing and FHIR transformation
resource "azurerm_linux_function_app" "main" {
  name                = local.names.function_app
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  # Function App configuration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"                   = "dotnet"
    "WEBSITE_RUN_FROM_PACKAGE"                  = "1"
    "APPINSIGHTS_INSTRUMENTATIONKEY"            = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.main.connection_string
    
    # IoT Hub connection for event processing
    "IOT_HUB_CONNECTION_STRING"                 = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=iot-hub-connection)"
    
    # FHIR service configuration
    "FHIR_URL"                                  = "https://${azurerm_healthcare_workspace.main.name}-${azurerm_healthcare_fhir_service.main.name}.fhir.azurehealthcareapis.com"
    "FHIR_AUDIENCE"                            = "https://azurehealthcareapis.com"
    
    # Healthcare-specific settings
    "HEALTH_DATA_RETENTION_DAYS"                = "2555"  # 7 years for healthcare compliance
    "ENABLE_AUDIT_LOGGING"                      = "true"
    "PATIENT_DATA_ENCRYPTION_ENABLED"           = "true"
  }

  # Configure Function App for healthcare compliance
  site_config {
    always_on                         = false  # Not needed for consumption plan
    ftps_state                       = "Disabled"
    http2_enabled                    = true
    minimum_tls_version              = "1.2"
    remote_debugging_enabled         = false
    use_32_bit_worker                = false
    
    application_stack {
      dotnet_version = "8.0"
    }

    # CORS configuration
    cors {
      allowed_origins     = ["*"]  # Restrict in production
      support_credentials = false
    }
  }

  # Enable HTTPS only for healthcare compliance
  https_only = true

  tags = local.common_tags
}

# Store IoT Hub connection string in Key Vault
resource "azurerm_key_vault_secret" "iot_hub_connection" {
  name         = "iot-hub-connection"
  value        = "HostName=${azurerm_iothub.main.hostname};SharedAccessKeyName=iothubowner;SharedAccessKey=${azurerm_iothub.main.shared_access_policy[0].primary_key}"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main, azurerm_iothub.main]
}

# Grant Function App access to Key Vault
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_function_app.main.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]

  depends_on = [azurerm_linux_function_app.main]
}

# Grant Function App access to FHIR service
resource "azurerm_role_assignment" "function_app_fhir" {
  scope                = azurerm_healthcare_fhir_service.main.id
  role_definition_name = "FHIR Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main, azurerm_healthcare_fhir_service.main]
}

# Diagnostic settings for IoT Hub
resource "azurerm_monitor_diagnostic_setting" "iot_hub" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "iot-hub-diagnostics"
  target_resource_id         = azurerm_iothub.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable key log categories for healthcare monitoring
  enabled_log {
    category = "Connections"
  }

  enabled_log {
    category = "DeviceTelemetry"
  }

  enabled_log {
    category = "C2DCommands"
  }

  enabled_log {
    category = "DeviceIdentityOperations"
  }

  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "function-app-diagnostics"
  target_resource_id         = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable function execution and performance logs
  enabled_log {
    category = "FunctionAppLogs"
  }

  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Health Data Services
resource "azurerm_monitor_diagnostic_setting" "health_workspace" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "health-workspace-diagnostics"
  target_resource_id         = azurerm_healthcare_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable audit logs for healthcare compliance
  enabled_log {
    category = "AuditLogs"
  }

  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Wait for diagnostic settings to be applied
resource "time_sleep" "wait_for_diagnostics" {
  depends_on = [
    azurerm_monitor_diagnostic_setting.iot_hub,
    azurerm_monitor_diagnostic_setting.function_app,
    azurerm_monitor_diagnostic_setting.health_workspace
  ]
  create_duration = "30s"
}