# Main Terraform configuration for Azure secure code execution workflow
# Implements Container Apps Dynamic Sessions with Event Grid integration

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all resources
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags     = var.resource_tags
}

# Create Log Analytics Workspace for monitoring and observability
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_config.sku
  retention_in_days   = var.log_analytics_config.retention_in_days
  daily_quota_gb      = var.log_analytics_config.daily_quota_gb
  tags                = var.resource_tags
}

# Create Application Insights for detailed application monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.resource_tags
}

# Create Azure Key Vault for secure secrets management
resource "azurerm_key_vault" "main" {
  name                        = "kv-${var.project_name}-${random_string.suffix.result}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = var.key_vault_config.enabled_for_disk_encryption
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = var.key_vault_config.soft_delete_retention_days
  purge_protection_enabled    = var.key_vault_config.purge_protection_enabled
  sku_name                    = var.key_vault_config.sku_name
  enable_rbac_authorization   = var.key_vault_config.enable_rbac_authorization
  tags                        = var.resource_tags

  # Network access rules for enhanced security
  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow" # Set to "Deny" for production with specific IP ranges
  }
}

# Create Storage Account for execution results and logs
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_config.account_tier
  account_replication_type = var.storage_config.account_replication_type
  access_tier              = var.storage_config.access_tier
  min_tls_version          = var.storage_config.min_tls_version
  https_traffic_only_enabled = var.storage_config.https_traffic_only
  tags                     = var.resource_tags

  # Enhanced security configuration
  blob_properties {
    versioning_enabled = true
    
    # Container delete retention policy
    delete_retention_policy {
      days = 7
    }
    
    # Blob delete retention policy
    container_delete_retention_policy {
      days = 7
    }
  }
}

# Create storage containers for execution results and logs
resource "azurerm_storage_container" "execution_results" {
  name                  = "execution-results"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "execution_logs" {
  name                  = "execution-logs"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create Container Apps Environment for hosting dynamic sessions
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project_name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = var.resource_tags

  # Configure workload profiles for better performance isolation
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

# Create Event Grid Topic for code execution events
resource "azurerm_eventgrid_topic" "main" {
  name                         = "egt-${var.project_name}-${random_string.suffix.result}"
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  input_schema                 = var.event_grid_config.input_schema
  public_network_access_enabled = var.event_grid_config.public_network_access_enabled
  local_auth_enabled           = var.event_grid_config.local_auth_enabled
  tags                         = var.resource_tags
}

# Create Service Plan for Function App (Consumption plan for cost optimization)
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = var.function_app_config.os_type
  sku_name            = "Y1" # Consumption plan for serverless execution
  tags                = var.resource_tags
}

# Create Function App for session management and event processing
resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  tags                = var.resource_tags

  # Configure managed identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }

  # Application settings for Function App configuration
  app_settings = {
    # Function runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_config.runtime_stack
    "FUNCTIONS_EXTENSION_VERSION"  = var.function_app_config.runtime_version
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    
    # Application Insights integration
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Container Apps and session management configuration
    "CONTAINER_APPS_ENVIRONMENT_ID" = azurerm_container_app_environment.main.id
    "SESSION_POOL_ENDPOINT"          = "https://${azurerm_container_app_environment.main.name}.${var.location}.azurecontainerapps.io"
    
    # Key Vault integration
    "KEY_VAULT_URL" = azurerm_key_vault.main.vault_uri
    
    # Storage Account configuration
    "STORAGE_ACCOUNT_NAME" = azurerm_storage_account.main.name
    
    # Event Grid configuration
    "EVENT_GRID_TOPIC_ENDPOINT" = azurerm_eventgrid_topic.main.endpoint
  }

  # Site configuration for enhanced security and performance
  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    # Security headers and CORS configuration
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
    
    # HTTP version and security settings
    http2_enabled       = true
    minimum_tls_version = "1.2"
    
    # Application insights configuration
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }
}

# Note: Azure Container Apps Session Pools are currently in preview and may not have
# complete Terraform provider support. This configuration shows the intended architecture.
# The session pool should be created manually or through Azure CLI until provider support is complete.

# Grant Function App access to Key Vault secrets
resource "azurerm_role_assignment" "function_app_key_vault" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Storage Account
resource "azurerm_role_assignment" "function_app_storage_blob" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Container Apps Environment
resource "azurerm_role_assignment" "function_app_container_apps" {
  scope                = azurerm_container_app_environment.main.id
  role_definition_name = "Container Apps Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Create Event Grid subscription to trigger Function App
resource "azurerm_eventgrid_event_subscription" "main" {
  name  = "code-execution-subscription"
  scope = azurerm_eventgrid_topic.main.id

  # Azure Function endpoint configuration
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.main.id}/functions/ProcessCodeExecution"
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }

  # Event filtering configuration
  subject_filter {
    subject_begins_with = "code-execution"
  }

  # Advanced filtering for specific event types
  advanced_filter {
    string_in {
      key    = "eventType"
      values = ["Microsoft.EventGrid.ExecuteCode", "Custom.CodeExecution"]
    }
  }

  # Retry policy for reliable event delivery
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440 # 24 hours
  }

  # Dead letter storage for failed events
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = "dead-letter-events"
  }
}

# Create dead letter container for failed events
resource "azurerm_storage_container" "dead_letter" {
  name                  = "dead-letter-events"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Store session pool management token in Key Vault (placeholder for manual configuration)
resource "azurerm_key_vault_secret" "session_pool_token" {
  name         = "session-pool-token"
  value        = "placeholder-token" # This should be updated with actual token
  key_vault_id = azurerm_key_vault.main.id
  tags         = var.resource_tags

  depends_on = [
    azurerm_role_assignment.function_app_key_vault
  ]
}

# Create diagnostic settings for comprehensive monitoring
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name               = "diag-${azurerm_linux_function_app.main.name}"
  target_resource_id = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable all available log categories
  enabled_log {
    category = "FunctionAppLogs"
  }

  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "container_app_environment" {
  name               = "diag-${azurerm_container_app_environment.main.name}"
  target_resource_id = azurerm_container_app_environment.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable container app logs
  enabled_log {
    category = "ContainerAppConsoleLogs"
  }

  enabled_log {
    category = "ContainerAppSystemLogs"
  }

  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "event_grid" {
  name               = "diag-${azurerm_eventgrid_topic.main.name}"
  target_resource_id = azurerm_eventgrid_topic.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable Event Grid specific logs
  enabled_log {
    category = "DeliveryFailures"
  }

  enabled_log {
    category = "PublishFailures"
  }

  # Enable metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}