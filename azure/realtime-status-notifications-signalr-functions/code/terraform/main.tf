# Main configuration for Real-time Status Notifications with SignalR and Functions
# This Terraform configuration creates the complete infrastructure for a serverless real-time notification system

# Generate random suffix for resource names to ensure uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Create Resource Group to contain all resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create Storage Account required by Azure Functions
# Functions require a storage account for code storage, logs, and runtime state
resource "azurerm_storage_account" "function_storage" {
  name                     = "${var.storage_account_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  tags = var.tags
}

# Create Application Insights for monitoring and diagnostics (optional but recommended)
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "log-${var.function_app_name}${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = var.tags
}

resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "appi-${var.function_app_name}${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  
  tags = var.tags
}

# Create Azure SignalR Service in Serverless mode
# Serverless mode is optimized for integration with Azure Functions
resource "azurerm_signalr_service" "main" {
  name                = "${var.signalr_name}${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # SKU configuration - Free_F1 provides 20 concurrent connections at no cost
  sku {
    name     = var.signalr_sku_name
    capacity = var.signalr_capacity
  }
  
  # Serverless mode for Azure Functions integration
  service_mode = var.signalr_service_mode
  
  # Enable CORS for web client access
  cors {
    allowed_origins = var.enable_cors_for_all_origins ? ["*"] : var.cors_allowed_origins
  }
  
  # Enable logging for diagnostics
  connectivity_logs_enabled = var.enable_signalr_logs
  messaging_logs_enabled    = var.enable_signalr_logs
  
  tags = var.tags
}

# Create App Service Plan for the Function App
# Using Consumption plan (Y1) for cost-effective serverless execution
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.function_app_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Windows"
  sku_name            = var.function_app_service_plan_sku_name
  
  tags = var.tags
}

# Create the Windows Function App
# This hosts the negotiate and broadcast functions for SignalR integration
resource "azurerm_windows_function_app" "main" {
  name                = "${var.function_app_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Link to App Service Plan and Storage Account
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Function App configuration
  functions_extension_version = var.functions_extension_version
  builtin_logging_enabled     = true
  
  # Security settings
  https_only                            = true
  public_network_access_enabled         = true
  ftp_publish_basic_authentication_enabled = false
  
  # Application settings for SignalR integration and runtime configuration
  app_settings = merge({
    # SignalR connection string for Functions bindings
    "AzureSignalRConnectionString" = azurerm_signalr_service.main.primary_connection_string
    
    # Functions runtime settings
    "FUNCTIONS_WORKER_RUNTIME" = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = var.node_version
    
    # Enable the Function App to run from package (recommended for deployments)
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    
    # SignalR hub name used by the functions
    "SignalRHubName" = "notifications"
  }, var.enable_application_insights ? {
    # Application Insights settings (only if enabled)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
  } : {})
  
  # Site configuration for the Function App
  site_config {
    # Enable Node.js runtime
    application_stack {
      node_version = var.node_version
    }
    
    # CORS configuration for web clients
    cors {
      allowed_origins     = var.enable_cors_for_all_origins ? ["*"] : var.cors_allowed_origins
      support_credentials = false
    }
    
    # Security and performance settings
    always_on                = false  # Should be false for Consumption plan
    use_32_bit_worker        = false  # Use 64-bit worker for better performance
    ftps_state              = "Disabled"
    http2_enabled           = true
    minimum_tls_version     = "1.2"
    
    # Application Insights integration
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  }
  
  # Enable system-assigned managed identity for secure access to other Azure resources
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
  
  # Ensure dependencies are created in the correct order
  depends_on = [
    azurerm_storage_account.function_storage,
    azurerm_signalr_service.main,
    azurerm_service_plan.main
  ]
}

# Output important information for verification and client configuration
output "signalr_hostname" {
  description = "The hostname of the SignalR service"
  value       = azurerm_signalr_service.main.hostname
  sensitive   = false
}

output "function_app_default_hostname" {
  description = "The default hostname of the Function App (for API endpoints)"
  value       = azurerm_windows_function_app.main.default_hostname
  sensitive   = false
}

output "function_app_name" {
  description = "The name of the deployed Function App"
  value       = azurerm_windows_function_app.main.name
  sensitive   = false
}

output "signalr_service_name" {
  description = "The name of the deployed SignalR service"
  value       = azurerm_signalr_service.main.name
  sensitive   = false
}

output "resource_group_name" {
  description = "The name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
  sensitive   = false
}

# Note: Connection strings and access keys are marked as sensitive for security
output "signalr_primary_connection_string" {
  description = "The primary connection string for the SignalR service (sensitive)"
  value       = azurerm_signalr_service.main.primary_connection_string
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "The Application Insights instrumentation key (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}