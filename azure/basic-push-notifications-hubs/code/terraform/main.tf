# Azure Notification Hubs Infrastructure Configuration
# This Terraform configuration creates a complete Azure Notification Hubs setup
# including resource group, namespace, and notification hub with proper security

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource Group
# Container for all notification hub resources with proper tagging
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name_prefix}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags

  lifecycle {
    create_before_destroy = false
  }
}

# Notification Hub Namespace
# Provides a unique messaging endpoint and security boundary for notification hubs
# Acts as a logical container that can host multiple notification hubs
resource "azurerm_notification_hub_namespace" "main" {
  name                = "${var.notification_hub_namespace_prefix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Free tier provides 1 million push notifications and 500 active devices
  # Suitable for development and small-scale applications
  namespace_type = var.namespace_sku
  
  tags = merge(var.tags, {
    resource_type = "notification-hub-namespace"
    sku          = var.namespace_sku
  })

  # Ensure proper resource dependencies
  depends_on = [azurerm_resource_group.main]
}

# Notification Hub
# Core component that manages device registrations and handles notification distribution
# Establishes the messaging endpoint for mobile applications and back-end services
resource "azurerm_notification_hub" "main" {
  name                = "${var.notification_hub_name_prefix}-${random_string.suffix.result}"
  namespace_name      = azurerm_notification_hub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = merge(var.tags, {
    resource_type = "notification-hub"
  })

  # Ensure proper resource dependencies
  depends_on = [azurerm_notification_hub_namespace.main]
}

# Data source to retrieve authorization rules for the notification hub
# These rules control access to hub operations with different permission levels
data "azurerm_notification_hub_authorization_rule" "listen" {
  name                = "DefaultListenSharedAccessSignature"
  notification_hub_id = azurerm_notification_hub.main.id

  depends_on = [azurerm_notification_hub.main]
}

data "azurerm_notification_hub_authorization_rule" "full" {
  name                = "DefaultFullSharedAccessSignature"  
  notification_hub_id = azurerm_notification_hub.main.id

  depends_on = [azurerm_notification_hub.main]
}

# Local values for better organization and reusability
locals {
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    terraform_managed = "true"
    deployment_date   = timestamp()
  })

  # Resource naming conventions
  resource_prefix = "${var.resource_group_name_prefix}-${random_string.suffix.result}"
  
  # Hub configuration details
  hub_config = {
    namespace_name = azurerm_notification_hub_namespace.main.name
    hub_name      = azurerm_notification_hub.main.name
    location      = azurerm_resource_group.main.location
  }
}