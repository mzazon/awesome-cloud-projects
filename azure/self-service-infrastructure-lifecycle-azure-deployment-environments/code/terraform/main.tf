# =============================================================================
# Main Infrastructure Configuration
# Self-Service Infrastructure Lifecycle with Azure Deployment Environments
# =============================================================================

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate unique suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming
locals {
  # Generate resource names with unique suffix
  resource_group_name    = var.resource_group_name != "" ? var.resource_group_name : "rg-devcenter-${var.project_name}-${random_string.suffix.result}"
  devcenter_name        = var.devcenter_name != "" ? var.devcenter_name : "dc-${var.project_name}-${random_string.suffix.result}"
  project_name          = var.devcenter_project_name != "" ? var.devcenter_project_name : "proj-${var.project_name}-${random_string.suffix.result}"
  storage_account_name  = var.storage_account_name != "" ? var.storage_account_name : "st${var.project_name}${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    environment        = var.environment
    project           = var.project_name
    deployment-method = "terraform"
    created-date      = formatdate("YYYY-MM-DD", timestamp())
  })
}

# =============================================================================
# Resource Group
# =============================================================================

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# =============================================================================
# Storage Account for Infrastructure Templates
# =============================================================================

# Storage account for storing ARM templates and infrastructure definitions
resource "azurerm_storage_account" "templates" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication
  
  # Security configurations
  https_traffic_only_enabled   = var.enable_https_traffic_only
  allow_nested_items_to_be_public = var.enable_public_access
  min_tls_version             = var.min_tls_version
  
  # Enable versioning and change feed for better management
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Lifecycle management policy
    delete_retention_policy {
      days = 30
    }
    
    container_delete_retention_policy {
      days = 30
    }
  }
  
  # Network access rules
  network_rules {
    default_action = "Allow"
    # Add IP restrictions in production environments
    bypass = ["AzureServices"]
  }
  
  tags = merge(local.common_tags, {
    purpose = "infrastructure-templates"
  })
}

# Container for storing infrastructure templates
resource "azurerm_storage_container" "templates" {
  name                  = "templates"
  storage_account_name  = azurerm_storage_account.templates.name
  container_access_type = "private"
}

# Sample web application ARM template
resource "azurerm_storage_blob" "webapp_template" {
  name                   = "webapp-environment.json"
  storage_account_name   = azurerm_storage_account.templates.name
  storage_container_name = azurerm_storage_container.templates.name
  type                   = "Block"
  
  source_content = jsonencode({
    "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    "contentVersion" = "1.0.0.0"
    "parameters" = {
      "appName" = {
        "type" = "string"
        "defaultValue" = "[concat('webapp-', uniqueString(resourceGroup().id))]"
        "metadata" = {
          "description" = "Name of the web application"
        }
      }
      "location" = {
        "type" = "string"
        "defaultValue" = "[resourceGroup().location]"
        "metadata" = {
          "description" = "Location for all resources"
        }
      }
      "environmentType" = {
        "type" = "string"
        "defaultValue" = "development"
        "allowedValues" = ["development", "staging", "production"]
        "metadata" = {
          "description" = "Environment type for appropriate configuration"
        }
      }
    }
    "variables" = {
      "appServicePlanName" = "[concat(parameters('appName'), '-plan')]"
      "appServicePlanSku" = "[if(equals(parameters('environmentType'), 'production'), 'P1v2', 'F1')]"
      "appServicePlanTier" = "[if(equals(parameters('environmentType'), 'production'), 'PremiumV2', 'Free')]"
    }
    "resources" = [
      {
        "type" = "Microsoft.Web/serverfarms"
        "apiVersion" = "2021-02-01"
        "name" = "[variables('appServicePlanName')]"
        "location" = "[parameters('location')]"
        "sku" = {
          "name" = "[variables('appServicePlanSku')]"
          "tier" = "[variables('appServicePlanTier')]"
        }
        "properties" = {
          "reserved" = false
        }
        "tags" = {
          "Environment" = "[parameters('environmentType')]"
          "CreatedBy" = "Azure Deployment Environments"
        }
      },
      {
        "type" = "Microsoft.Web/sites"
        "apiVersion" = "2021-02-01"
        "name" = "[parameters('appName')]"
        "location" = "[parameters('location')]"
        "dependsOn" = [
          "[resourceId('Microsoft.Web/serverfarms', variables('appServicePlanName'))]"
        ]
        "properties" = {
          "serverFarmId" = "[resourceId('Microsoft.Web/serverfarms', variables('appServicePlanName'))]"
          "httpsOnly" = true
          "siteConfig" = {
            "minTlsVersion" = "1.2"
            "ftpsState" = "Disabled"
          }
        }
        "tags" = {
          "Environment" = "[parameters('environmentType')]"
          "CreatedBy" = "Azure Deployment Environments"
        }
      }
    ]
    "outputs" = {
      "webAppUrl" = {
        "type" = "string"
        "value" = "[concat('https://', reference(parameters('appName')).defaultHostName)]"
      }
      "webAppName" = {
        "type" = "string"
        "value" = "[parameters('appName')]"
      }
      "resourceGroupName" = {
        "type" = "string"
        "value" = "[resourceGroup().name]"
      }
    }
  })
}

# Environment manifest for Azure Developer CLI integration
resource "azurerm_storage_blob" "environment_manifest" {
  name                   = "environment.yaml"
  storage_account_name   = azurerm_storage_account.templates.name
  storage_container_name = azurerm_storage_container.templates.name
  type                   = "Block"
  
  source_content = yamlencode({
    name = "WebApp Environment"
    version = "1.0.0"
    summary = "Standard web application environment with App Service"
    description = "Deploys a web application using Azure App Service with configurable SKU based on environment type"
    runner = "ARM"
    templatePath = "webapp-environment.json"
    parameters = [
      {
        id = "appName"
        name = "Application Name"
        description = "Name of the web application"
        type = "string"
        required = false
      },
      {
        id = "environmentType"
        name = "Environment Type"
        description = "Environment type for appropriate configuration"
        type = "string"
        required = true
        allowed = ["development", "staging", "production"]
      }
    ]
  })
}

# =============================================================================
# Azure DevCenter
# =============================================================================

# Azure DevCenter - Central hub for development environments
resource "azurerm_dev_center" "main" {
  name                = local.devcenter_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Enable system-assigned managed identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    purpose = "development-environments"
    tier    = "platform"
  })
}

# Environment types for different deployment targets
resource "azurerm_dev_center_environment_type" "environment_types" {
  for_each = { for env in var.environment_types : env.name => env }
  
  name          = each.value.name
  dev_center_id = azurerm_dev_center.main.id
  
  tags = merge(local.common_tags, each.value.tags)
}

# DevCenter catalog linking to our storage account
resource "azurerm_dev_center_catalog" "main" {
  name                = var.catalog_name
  dev_center_id       = azurerm_dev_center.main.id
  resource_group_name = azurerm_resource_group.main.name
  
  # Use GitHub catalog type for template repository
  catalog_github {
    branch = "main"
    path   = "/"
    uri    = "https://github.com/Azure/deployment-environments.git"
  }
  
  depends_on = [
    azurerm_storage_blob.webapp_template,
    azurerm_storage_blob.environment_manifest
  ]
}

# =============================================================================
# DevCenter Project
# =============================================================================

# DevCenter project for organizing development teams
resource "azurerm_dev_center_project" "main" {
  name                = local.project_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  dev_center_id       = azurerm_dev_center.main.id
  
  description = "Self-service infrastructure lifecycle project enabling developers to provision and manage environments on-demand"
  
  # Enable managed identity for secure resource access
  identity {
    type = "SystemAssigned"
  }
  
  # Configure maximum resources per user to control costs
  maximum_dev_boxes_per_user = var.max_environments_per_user
  
  tags = merge(local.common_tags, {
    purpose = "development-project"
    team    = "development"
  })
}

# Project environment types - associate environment types with the project
resource "azurerm_dev_center_project_environment_type" "project_environment_types" {
  for_each = { for env in var.environment_types : env.name => env }
  
  name                         = each.value.name
  location                     = azurerm_resource_group.main.location
  dev_center_project_id        = azurerm_dev_center_project.main.id
  deployment_target_id         = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Configure creator role assignments for self-service capabilities
  creator_role_assignment_roles = [
    "Owner",
    "Contributor"
  ]
  
  # Configure user role assignments for project access
  user_role_assignment {
    user_id = data.azurerm_client_config.current.object_id
    roles   = ["DevCenter Project Admin"]
  }
  
  tags = merge(local.common_tags, each.value.tags)
}

# =============================================================================
# RBAC Assignments
# =============================================================================

# Grant DevCenter managed identity necessary permissions
resource "azurerm_role_assignment" "devcenter_contributor" {
  count                = var.enable_rbac_assignments ? 1 : 0
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_dev_center.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "devcenter_user_access_admin" {
  count                = var.enable_rbac_assignments ? 1 : 0
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "User Access Administrator"
  principal_id         = azurerm_dev_center.main.identity[0].principal_id
}

# Grant DevCenter managed identity access to storage account
resource "azurerm_role_assignment" "devcenter_storage_reader" {
  count                = var.enable_rbac_assignments ? 1 : 0
  scope                = azurerm_storage_account.templates.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_dev_center.main.identity[0].principal_id
}

# Grant current user Deployment Environments User role
resource "azurerm_role_assignment" "user_deployment_environments" {
  count                = var.enable_rbac_assignments ? 1 : 0
  scope                = azurerm_dev_center_project.main.id
  role_definition_name = "Deployment Environments User"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant project environment type managed identities necessary permissions
resource "azurerm_role_assignment" "project_env_type_contributor" {
  for_each = var.enable_rbac_assignments ? { for env in var.environment_types : env.name => env } : {}
  
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_dev_center_project_environment_type.project_environment_types[each.key].identity[0].principal_id
}

# =============================================================================
# Monitoring and Logging
# =============================================================================

# Log Analytics workspace for monitoring (optional)
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.common_tags, {
    purpose = "monitoring"
  })
}

# Application Insights for application monitoring (optional)
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  
  tags = merge(local.common_tags, {
    purpose = "application-monitoring"
  })
}

# =============================================================================
# Cost Management
# =============================================================================

# Budget for cost management
resource "azurerm_consumption_budget_resource_group" "main" {
  name              = "budget-${var.project_name}-${random_string.suffix.result}"
  resource_group_id = azurerm_resource_group.main.id
  
  amount     = var.cost_management_budget
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = formatdate("YYYY-MM-01'T'00:00:00'Z'", timeadd(timestamp(), "8760h")) # 1 year
  }
  
  # Notifications for budget alerts
  dynamic "notification" {
    for_each = length(var.notification_emails) > 0 ? [1] : []
    content {
      enabled        = true
      threshold      = var.budget_alert_threshold_actual
      operator       = "GreaterThan"
      threshold_type = "Actual"
      
      contact_emails = var.notification_emails
    }
  }
  
  dynamic "notification" {
    for_each = length(var.notification_emails) > 0 ? [1] : []
    content {
      enabled        = true
      threshold      = var.budget_alert_threshold_forecast
      operator       = "GreaterThan"
      threshold_type = "Forecasted"
      
      contact_emails = var.notification_emails
    }
  }
}

# =============================================================================
# Wait for Resource Provisioning
# =============================================================================

# Wait for DevCenter to be fully provisioned before completing
resource "time_sleep" "wait_for_devcenter" {
  depends_on = [
    azurerm_dev_center.main,
    azurerm_dev_center_catalog.main,
    azurerm_dev_center_project.main
  ]
  
  create_duration = "60s"
}