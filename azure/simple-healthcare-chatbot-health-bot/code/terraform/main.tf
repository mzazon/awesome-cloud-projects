# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent naming and tagging
locals {
  # Resource naming with random suffix
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  health_bot_name     = var.health_bot_name != "" ? var.health_bot_name : "${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    environment       = var.environment
    project          = var.project_name
    deployment_date  = timestamp()
    terraform        = "true"
  })
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Resource Group for Health Bot resources
resource "azurerm_resource_group" "health_bot_rg" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags

  lifecycle {
    ignore_changes = [tags["deployment_date"]]
  }
}

# Azure Health Bot Service Instance
resource "azurerm_healthbot" "health_bot" {
  name                = local.health_bot_name
  resource_group_name = azurerm_resource_group.health_bot_rg.name
  location            = azurerm_resource_group.health_bot_rg.location
  sku_name            = var.health_bot_sku
  tags                = local.common_tags

  lifecycle {
    ignore_changes = [tags["deployment_date"]]
  }
}

# Optional: Role assignment for Health Bot service to access other Azure resources
# This is useful for integrating with other Azure services like Logic Apps, FHIR, etc.
resource "azurerm_role_assignment" "health_bot_contributor" {
  count                = var.enable_hipaa_compliance ? 1 : 0
  scope                = azurerm_resource_group.health_bot_rg.id
  role_definition_name = "Health Bot Contributor"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [azurerm_healthbot.health_bot]
}

# Optional: Application Insights for Health Bot monitoring and analytics
# This provides detailed analytics about bot conversations and performance
resource "azurerm_application_insights" "health_bot_insights" {
  count               = var.enable_hipaa_compliance ? 1 : 0
  name                = "ai-${local.health_bot_name}"
  location            = azurerm_resource_group.health_bot_rg.location
  resource_group_name = azurerm_resource_group.health_bot_rg.name
  application_type    = "web"
  retention_in_days   = 90  # HIPAA compliance consideration
  tags                = local.common_tags

  lifecycle {
    ignore_changes = [tags["deployment_date"]]
  }
}