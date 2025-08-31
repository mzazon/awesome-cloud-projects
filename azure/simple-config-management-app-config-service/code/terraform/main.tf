# Azure Configuration Management Solution with App Configuration and App Service
# This Terraform configuration creates a complete solution for centralized configuration management
# including Azure App Configuration, App Service, and necessary supporting resources

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for computed resource names and common configurations
locals {
  # Generate resource names with consistent naming convention
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  app_config_name     = var.app_config_name != null ? var.app_config_name : "appconfig-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  app_service_name    = var.app_service_name != null ? var.app_service_name : "webapp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  app_service_plan_name = "plan-${local.app_service_name}"
  
  # Common tags to be applied to all resources
  common_tags = merge(var.common_tags, {
    Project     = var.project_name
    Environment = var.environment
    DeployedBy  = "Terraform"
    Recipe      = "simple-config-management-app-config-service"
  })
  
  # Application Insights name
  app_insights_name = var.enable_application_insights ? "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}" : null
}

# Resource Group
# Logical container for grouping related Azure resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Azure App Configuration Store
# Centralized configuration management service for applications
resource "azurerm_app_configuration" "main" {
  name                       = local.app_config_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  sku                        = var.app_config_sku
  local_auth_enabled         = var.app_config_local_auth_enabled
  public_network_access      = var.app_config_public_network_access
  purge_protection_enabled   = false # Set to false for demo purposes
  soft_delete_retention_days = 1     # Minimum value for cost optimization
  
  tags = local.common_tags
}

# App Configuration Key-Value Pairs
# Store application configuration settings as key-value pairs
resource "azurerm_app_configuration_key" "config_values" {
  for_each = var.configuration_values

  configuration_store_id = azurerm_app_configuration.main.id
  key                    = each.key
  value                  = each.value.value
  content_type          = each.value.content_type
  label                 = each.value.label
  
  # Ensure App Configuration store is fully provisioned before creating keys
  depends_on = [azurerm_role_assignment.app_config_data_owner]
}

# Role Assignment for Terraform Service Principal
# Grant App Configuration Data Owner role to allow Terraform to manage configuration keys
resource "azurerm_role_assignment" "app_config_data_owner" {
  scope                = azurerm_app_configuration.main.id
  role_definition_name = "App Configuration Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Application Insights (Optional)
# Application Performance Monitoring service for the web application
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = var.application_insights_type
  
  tags = local.common_tags
}

# App Service Plan
# Compute resources and pricing tier for hosting the web application
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = var.app_service_os_type
  sku_name            = var.app_service_plan_sku
  
  tags = local.common_tags
}

# Linux Web App
# Azure App Service instance for hosting the ASP.NET Core web application
resource "azurerm_linux_web_app" "main" {
  count = var.app_service_os_type == "Linux" ? 1 : 0
  
  name                      = local.app_service_name
  resource_group_name       = azurerm_resource_group.main.name
  location                  = azurerm_service_plan.main.location
  service_plan_id           = azurerm_service_plan.main.id
  https_only               = var.https_only
  public_network_access_enabled = true
  
  # Enable system-assigned managed identity for secure authentication
  identity {
    type = var.managed_identity_enabled ? "SystemAssigned" : null
  }
  
  # Application configuration and runtime settings
  site_config {
    always_on                         = var.app_service_plan_sku != "F1" && var.app_service_plan_sku != "D1" ? var.always_on : false
    http2_enabled                     = true
    minimum_tls_version              = var.minimum_tls_version
    use_32_bit_worker                = var.app_service_plan_sku == "F1" || var.app_service_plan_sku == "D1" ? true : false
    
    # Configure .NET runtime stack
    application_stack {
      dotnet_version = var.dotnet_version
    }
    
    # Configure health check path
    health_check_path = "/"
  }
  
  # Application settings and connection strings
  app_settings = merge(
    {
      "APP_CONFIG_ENDPOINT" = azurerm_app_configuration.main.endpoint
      "ASPNETCORE_ENVIRONMENT" = title(var.environment)
      "ASPNETCORE_LOGGING__CONSOLE__DISABLECOLORS" = "true"
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    },
    var.enable_application_insights ? {
      "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main[0].instrumentation_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
    } : {}
  )
  
  tags = local.common_tags
  
  # Ensure App Configuration and managed identity are ready
  depends_on = [
    azurerm_app_configuration.main,
    azurerm_role_assignment.app_config_data_reader
  ]
}

# Windows Web App (Alternative configuration for Windows hosting)
resource "azurerm_windows_web_app" "main" {
  count = var.app_service_os_type == "Windows" ? 1 : 0
  
  name                      = local.app_service_name
  resource_group_name       = azurerm_resource_group.main.name
  location                  = azurerm_service_plan.main.location
  service_plan_id           = azurerm_service_plan.main.id
  https_only               = var.https_only
  public_network_access_enabled = true
  
  # Enable system-assigned managed identity for secure authentication
  identity {
    type = var.managed_identity_enabled ? "SystemAssigned" : null
  }
  
  # Application configuration and runtime settings
  site_config {
    always_on                         = var.app_service_plan_sku != "F1" && var.app_service_plan_sku != "D1" ? var.always_on : false
    http2_enabled                     = true
    minimum_tls_version              = var.minimum_tls_version
    use_32_bit_worker                = var.app_service_plan_sku == "F1" || var.app_service_plan_sku == "D1" ? true : false
    
    # Configure .NET runtime stack
    application_stack {
      dotnet_version = "v${var.dotnet_version}"
      current_stack  = "dotnet"
    }
    
    # Configure health check path
    health_check_path = "/"
  }
  
  # Application settings and connection strings
  app_settings = merge(
    {
      "APP_CONFIG_ENDPOINT" = azurerm_app_configuration.main.endpoint
      "ASPNETCORE_ENVIRONMENT" = title(var.environment)
      "ASPNETCORE_LOGGING__CONSOLE__DISABLECOLORS" = "true"
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    },
    var.enable_application_insights ? {
      "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main[0].instrumentation_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
    } : {}
  )
  
  tags = local.common_tags
  
  # Ensure App Configuration and managed identity are ready
  depends_on = [
    azurerm_app_configuration.main,
    azurerm_role_assignment.app_config_data_reader
  ]
}

# Role Assignment for App Service Managed Identity
# Grant App Configuration Data Reader role to the web app's managed identity
resource "azurerm_role_assignment" "app_config_data_reader" {
  count = var.managed_identity_enabled ? 1 : 0
  
  scope                = azurerm_app_configuration.main.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].identity[0].principal_id : azurerm_windows_web_app.main[0].identity[0].principal_id
  
  depends_on = [
    azurerm_linux_web_app.main,
    azurerm_windows_web_app.main
  ]
}

# Optional: Deployment slot for staging (only for paid tiers)
resource "azurerm_linux_web_app_slot" "staging" {
  count = var.app_service_os_type == "Linux" && var.app_service_plan_sku != "F1" && var.app_service_plan_sku != "D1" && var.environment == "prod" ? 1 : 0
  
  name           = "staging"
  app_service_id = azurerm_linux_web_app.main[0].id
  https_only     = var.https_only
  
  # Enable system-assigned managed identity for secure authentication
  identity {
    type = var.managed_identity_enabled ? "SystemAssigned" : null
  }
  
  # Inherit site configuration from production slot
  site_config {
    always_on           = var.always_on
    http2_enabled       = true
    minimum_tls_version = var.minimum_tls_version
    
    application_stack {
      dotnet_version = var.dotnet_version
    }
  }
  
  # Staging-specific application settings
  app_settings = merge(
    {
      "APP_CONFIG_ENDPOINT" = azurerm_app_configuration.main.endpoint
      "ASPNETCORE_ENVIRONMENT" = "Staging"
      "ASPNETCORE_LOGGING__CONSOLE__DISABLECOLORS" = "true"
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    },
    var.enable_application_insights ? {
      "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main[0].instrumentation_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
    } : {}
  )
  
  tags = local.common_tags
}

# Role Assignment for Staging Slot Managed Identity (if applicable)
resource "azurerm_role_assignment" "staging_app_config_data_reader" {
  count = var.managed_identity_enabled && var.app_service_os_type == "Linux" && var.app_service_plan_sku != "F1" && var.app_service_plan_sku != "D1" && var.environment == "prod" ? 1 : 0
  
  scope                = azurerm_app_configuration.main.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
  
  depends_on = [azurerm_linux_web_app_slot.staging]
}

# Optional: Custom Domain and SSL Certificate
# Uncomment and configure if you have a custom domain
# resource "azurerm_app_service_custom_hostname_binding" "main" {
#   hostname            = "your-custom-domain.com"
#   app_service_name    = var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].name : azurerm_windows_web_app.main[0].name
#   resource_group_name = azurerm_resource_group.main.name
# }

# Optional: App Service Virtual Network Integration
# Uncomment if you want to integrate with a virtual network
# resource "azurerm_app_service_virtual_network_swift_connection" "main" {
#   app_service_id = var.app_service_os_type == "Linux" ? azurerm_linux_web_app.main[0].id : azurerm_windows_web_app.main[0].id
#   subnet_id      = var.subnet_id
# }