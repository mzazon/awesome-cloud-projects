# Azure Maps Store Locator Infrastructure
# This Terraform configuration creates the necessary Azure resources for a web-based store locator
# using Azure Maps services with interactive mapping, search, and location clustering capabilities

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  count       = var.generate_random_suffix ? 1 : 0
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Create unique suffix for resource names if enabled
  resource_suffix = var.generate_random_suffix ? random_id.suffix[0].hex : ""
  
  # Construct unique resource names
  resource_group_name = var.generate_random_suffix ? "${var.resource_group_name}-${local.resource_suffix}" : var.resource_group_name
  maps_account_name   = var.generate_random_suffix ? "${var.maps_account_name}${local.resource_suffix}" : var.maps_account_name
  
  # Common tags to be applied to all resources
  common_tags = merge(
    var.tags,
    {
      CreatedDate = formatdate("YYYY-MM-DD", timestamp())
      Recipe      = "simple-store-locator-azure-maps"
    }
  )
}

# Create Resource Group for all store locator resources
# This groups all related resources together for easier management and cost tracking
resource "azurerm_resource_group" "store_locator" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags

  lifecycle {
    # Prevent accidental deletion of the resource group
    prevent_destroy = false
  }
}

# Create Azure Maps Account for geospatial services
# Azure Maps provides interactive mapping, search, and location-based services
# Gen2 pricing tier offers enterprise-grade features with generous free tier (1,000 transactions/month)
resource "azurerm_maps_account" "store_locator" {
  name                         = local.maps_account_name
  resource_group_name          = azurerm_resource_group.store_locator.name
  location                     = azurerm_resource_group.store_locator.location
  sku_name                     = var.maps_sku_name
  local_authentication_enabled = var.local_authentication_enabled
  tags                         = local.common_tags

  # Configure CORS for web browser access from different domains
  # This enables the store locator web application to access Azure Maps APIs
  cors {
    allowed_origins = var.cors_allowed_origins
  }

  # Configure managed identity if enabled for enhanced security
  dynamic "identity" {
    for_each = var.enable_system_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  # Set timeouts for resource operations
  timeouts {
    create = "30m"
    read   = "5m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [azurerm_resource_group.store_locator]
}

# Output important information for application configuration and verification
# These outputs provide the necessary information to configure the web application
# and verify the successful deployment of Azure Maps resources