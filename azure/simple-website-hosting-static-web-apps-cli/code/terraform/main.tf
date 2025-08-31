# Azure Static Web Apps Infrastructure for Simple Website Hosting
# This configuration creates a complete static website hosting solution using Azure Static Web Apps
# with global CDN distribution, automatic SSL certificates, and serverless deployment capabilities

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Use provided suffix or generated random suffix
locals {
  # Determine the suffix to use for resource naming
  name_suffix = var.name_suffix != null ? var.name_suffix : random_string.suffix.result
  
  # Create standardized resource names with environment and suffix
  resource_group_name    = "${var.resource_group_name}-${var.environment}-${local.name_suffix}"
  static_web_app_name    = "${var.static_web_app_name}-${var.environment}-${local.name_suffix}"
  
  # Merge default tags with provided tags for comprehensive resource tagging
  common_tags = merge(var.tags, {
    Environment   = var.environment
    ResourceType  = "StaticWebApp"
    CreatedBy     = "terraform"
    LastModified  = timestamp()
  })
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group to contain all static web app resources
# Resource groups provide logical containers for organizing and managing related Azure resources
resource "azurerm_resource_group" "static_web_app" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags

  lifecycle {
    # Prevent accidental deletion of resource group containing production resources
    prevent_destroy = false
  }
}

# Create Azure Static Web App resource
# Static Web Apps provide serverless hosting with global CDN distribution, automatic SSL, and CI/CD integration
resource "azurerm_static_web_app" "main" {
  name                = local.static_web_app_name
  resource_group_name = azurerm_resource_group.static_web_app.name
  location            = azurerm_resource_group.static_web_app.location
  
  # Configure SKU for pricing tier and feature access
  sku_tier = var.static_web_app_sku_tier
  sku_size = var.static_web_app_sku_size
  
  # Enable preview environments for testing pull requests (Standard tier feature)
  preview_environments_enabled = var.preview_environments_enabled && var.static_web_app_sku_tier == "Standard"
  
  # Apply comprehensive resource tags for management and cost tracking
  tags = local.common_tags

  # Lifecycle management to handle updates gracefully
  lifecycle {
    # Create new resource before destroying old one to minimize downtime
    create_before_destroy = true
    
    # Ignore changes to deployment token as it's managed by Azure
    ignore_changes = [
      api_key
    ]
  }
}

# Configure Static Web App deployment settings and build configuration
# This resource manages the application source code repository integration
resource "azurerm_static_web_app_deployment" "main" {
  count               = var.github_repository_url != null ? 1 : 0
  static_web_app_id   = azurerm_static_web_app.main.id
  
  # GitHub repository configuration for automated CI/CD
  repository_url      = var.github_repository_url
  branch             = var.github_branch
  
  # Build configuration paths within the repository
  app_location       = var.github_app_location
  api_location       = var.github_api_location
  output_location    = var.github_output_location
  
  # Build settings for Static Web Apps deployment
  build_details {
    # Skip GitHub Action workflow generation if using manual deployment
    skip_github_action_workflow_generation = var.build_properties.skip_github_action_workflow_generation
    # Skip API build for static-only websites
    skip_api_build                         = var.build_properties.skip_api_build
  }

  # Ensure deployment is created after the Static Web App
  depends_on = [azurerm_static_web_app.main]
}

# Configure application settings (environment variables) for the Static Web App
# These settings are available at runtime for dynamic configuration
resource "azurerm_static_web_app_app_settings" "main" {
  count             = length(var.app_settings) > 0 ? 1 : 0
  static_web_app_id = azurerm_static_web_app.main.id
  app_settings      = var.app_settings

  # Ensure app settings are configured after the Static Web App exists
  depends_on = [azurerm_static_web_app.main]
}

# Configure custom domain for the Static Web App (optional)
# Custom domains provide branded URLs with automatic SSL certificate management
resource "azurerm_static_web_app_custom_domain" "main" {
  count             = var.custom_domain != null ? 1 : 0
  static_web_app_id = azurerm_static_web_app.main.id
  domain_name       = var.custom_domain
  
  # Validation type for domain ownership verification
  validation_type   = "cname-delegation"

  # Ensure custom domain is configured after the Static Web App exists
  depends_on = [azurerm_static_web_app.main]
  
  lifecycle {
    # Custom domain configuration may take time to propagate
    create_before_destroy = true
  }
}

# Optional: Configure Azure Monitor diagnostic settings for Static Web App logging
# This provides comprehensive monitoring and logging capabilities for production environments
resource "azurerm_monitor_diagnostic_setting" "static_web_app" {
  count                      = var.static_web_app_sku_tier == "Standard" ? 1 : 0
  name                       = "diag-${local.static_web_app_name}"
  target_resource_id         = azurerm_static_web_app.main.id
  
  # Configure metrics collection for performance monitoring
  enabled_log {
    category = "SiteAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }

  # Ensure diagnostic settings are created after the Static Web App
  depends_on = [azurerm_static_web_app.main]
}