# Azure Weather Dashboard Infrastructure
# This Terraform configuration creates a serverless weather dashboard using
# Azure Static Web Apps with integrated Azure Functions for backend API

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create resource group for all weather dashboard resources
resource "azurerm_resource_group" "weather_dashboard" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    "ResourceType" = "ResourceGroup"
    "CreatedDate"  = timestamp()
  })

  lifecycle {
    ignore_changes = [
      tags["CreatedDate"]
    ]
  }
}

# Create Azure Static Web App with integrated Functions
resource "azurerm_static_web_app" "weather_dashboard" {
  name                = "swa-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.weather_dashboard.name
  location            = azurerm_resource_group.weather_dashboard.location

  # Static Web App configuration
  sku_tier                            = var.static_web_app_sku_tier
  sku_size                            = var.static_web_app_sku_size
  preview_environments_enabled        = var.preview_environments_enabled
  configuration_file_changes_enabled  = var.configuration_file_changes_enabled
  public_network_access_enabled       = var.public_network_access_enabled

  # Application settings for the integrated Functions
  app_settings = {
    # OpenWeatherMap API key for weather data fetching
    "OPENWEATHER_API_KEY" = var.openweather_api_key
    
    # Azure Functions runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    
    # Application insights for monitoring (automatically configured)
    "APPINSIGHTS_INSTRUMENTATIONKEY" = "@Microsoft.KeyVault(SecretUri=${azurerm_static_web_app.weather_dashboard.default_host_name})"
    
    # Static Web App specific settings
    "SKIP_APP_BUILD" = "true"
  }

  # Optional GitHub repository integration for CI/CD
  repository_url    = var.repository_url != "" ? var.repository_url : null
  repository_branch = var.repository_url != "" ? var.repository_branch : null
  repository_token  = var.repository_url != "" && var.repository_token != "" ? var.repository_token : null

  tags = merge(var.tags, {
    "ResourceType" = "StaticWebApp"
    "Service"      = "AzureStaticWebApps"
    "Component"    = "Frontend"
  })

  # Ensure resource group is created first
  depends_on = [azurerm_resource_group.weather_dashboard]

  lifecycle {
    # Prevent accidental deletion of the Static Web App
    prevent_destroy = false
    
    # Ignore changes to repository token to prevent plan changes
    ignore_changes = [
      repository_token
    ]
  }
}

# Create a custom domain for the Static Web App (optional, commented out by default)
# Uncomment and configure if you have a custom domain
# resource "azurerm_static_web_app_custom_domain" "weather_dashboard" {
#   static_web_app_id = azurerm_static_web_app.weather_dashboard.id
#   domain_name       = "weather.yourdomain.com"
#   validation_type   = "cname-delegation"
# }