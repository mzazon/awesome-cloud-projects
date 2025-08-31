# Main Terraform configuration for text sentiment analysis solution
# This file creates the core infrastructure components

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent naming and configuration
locals {
  # Generate unique resource names with random suffix
  resource_suffix           = random_string.suffix.result
  resource_group_name      = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  cognitive_services_name  = "lang-${var.project_name}-${local.resource_suffix}"
  storage_account_name     = "st${var.project_name}${local.resource_suffix}"
  function_app_name        = "func-${var.project_name}-${local.resource_suffix}"
  app_service_plan_name    = "asp-${var.project_name}-${local.resource_suffix}"
  app_insights_name        = "ai-${var.project_name}-${local.resource_suffix}"
  log_analytics_name       = "law-${var.project_name}-${local.resource_suffix}"
  
  # Merge default tags with user-provided tags
  common_tags = merge(var.tags, {
    Environment   = var.environment
    DeployedBy    = "Terraform"
    LastModified  = timestamp()
  })
}

# Create the resource group for all resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Log Analytics Workspace for Application Insights
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# Create Application Insights for monitoring and telemetry
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  tags                = local.common_tags
}

# Create Azure Cognitive Services Language resource for sentiment analysis
resource "azurerm_cognitive_account" "language" {
  name                = local.cognitive_services_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "TextAnalytics"
  sku_name            = var.cognitive_services_sku
  
  # Configure custom subdomain for the service
  custom_subdomain_name = local.cognitive_services_name
  
  # Enable public network access (can be restricted in production)
  public_network_access_enabled = true
  
  # Configure identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Create storage account for Function App runtime and data
resource "azurerm_storage_account" "function_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Configure access tier for cost optimization
  access_tier = "Hot"
  
  # Enable secure transfer and configure TLS version
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Configure blob properties for security
  blob_properties {
    versioning_enabled       = false
    change_feed_enabled      = false
    default_service_version  = "2020-06-12"
    last_access_time_enabled = false
    
    # Configure container delete retention (disabled for demo)
    container_delete_retention_policy {
      days = 1
    }
    
    # Configure blob delete retention (disabled for demo)
    delete_retention_policy {
      days = 1
    }
  }
  
  # Configure network access (open for demo, restrict in production)
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  tags = local.common_tags
}

# Create App Service Plan for the Function App
resource "azurerm_service_plan" "function_plan" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Configure OS and SKU based on requirements
  os_type  = "Linux"
  sku_name = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

# Create the Linux Function App for sentiment analysis
resource "azurerm_linux_function_app" "sentiment_function" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.function_plan.id
  
  # Configure storage account connection
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Configure Function App settings
  site_config {
    # Set Python version and function runtime
    application_stack {
      python_version = var.python_version
    }
    
    # Configure CORS for web applications (adjust as needed)
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
    
    # Configure function execution settings
    always_on                         = false  # Not supported in consumption plan
    use_32_bit_worker                = false
    ftps_state                       = "FtpsOnly"
    http2_enabled                    = true
    scm_use_main_ip_restriction     = false
    scm_minimum_tls_version         = "1.2"
    minimum_tls_version             = "1.2"
  }
  
  # Configure application settings for the function
  app_settings = merge({
    # Function runtime settings
    "FUNCTIONS_EXTENSION_VERSION" = "~4"
    "FUNCTIONS_WORKER_RUNTIME"    = "python"
    "WEBSITE_RUN_FROM_PACKAGE"    = "1"
    
    # Azure Cognitive Services configuration
    "LANGUAGE_ENDPOINT" = azurerm_cognitive_account.language.endpoint
    "LANGUAGE_KEY"      = azurerm_cognitive_account.language.primary_access_key
    
    # Function execution settings
    "functionTimeout" = "00:0${var.function_timeout_duration < 60 ? 0 : floor(var.function_timeout_duration / 60)}:${format("%02d", var.function_timeout_duration % 60)}"
    
  }, var.enable_application_insights ? {
    # Application Insights configuration (if enabled)
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
  } : {})
  
  # Configure system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Configure connection strings (if needed for advanced scenarios)
  connection_string {
    name  = "DefaultConnection"
    type  = "SQLAzure"
    value = "Server=tcp:example.database.windows.net,1433;Database=example;User ID=example;Password=example;Encrypt=true;Connection Timeout=30;"
  }
  
  tags = local.common_tags
  
  # Ensure storage account is created before function app
  depends_on = [
    azurerm_storage_account.function_storage,
    azurerm_cognitive_account.language
  ]
}

# Create a storage container for function packages (optional)
resource "azurerm_storage_container" "function_packages" {
  name                  = "function-packages"
  storage_account_name  = azurerm_storage_account.function_storage.name
  container_access_type = "private"
}

# Configure RBAC role assignment for Function App to access Cognitive Services
resource "azurerm_role_assignment" "function_cognitive_services" {
  scope                = azurerm_cognitive_account.language.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.sentiment_function.identity[0].principal_id
}

# Configure RBAC role assignment for Function App to access Storage Account
resource "azurerm_role_assignment" "function_storage" {
  scope                = azurerm_storage_account.function_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.sentiment_function.identity[0].principal_id
}