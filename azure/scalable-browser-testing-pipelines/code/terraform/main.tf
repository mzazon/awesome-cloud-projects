# Main Terraform configuration for Azure Playwright Testing with Azure DevOps
# This file creates the complete infrastructure for automated browser testing pipelines

# Data sources for current Azure context
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with consistent prefix and random suffix
  resource_prefix = "${var.project_name}-${var.environment}"
  random_suffix   = random_string.suffix.result
  
  # Resource names with uniqueness guarantees
  playwright_workspace_name = var.playwright_workspace_name != "" ? var.playwright_workspace_name : "pw-workspace-${local.random_suffix}"
  acr_name                 = var.acr_name != "" ? var.acr_name : "acr${local.random_suffix}"
  key_vault_name           = var.key_vault_name != "" ? var.key_vault_name : "kv-${local.random_suffix}"
  
  # Common tags merged with user-defined tags
  common_tags = merge(var.tags, {
    ResourcePrefix = local.resource_prefix
    CreatedBy      = "Terraform"
    CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group for all Azure resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Azure Container Registry for storing test container images
resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = var.acr_admin_enabled
  
  # Enable content trust for production environments
  trust_policy {
    enabled = var.environment == "production"
  }
  
  # Configure retention policy for managing storage costs
  retention_policy {
    enabled = true
    days    = var.environment == "production" ? 30 : 7
  }
  
  # Enable quarantine policy for security scanning
  quarantine_policy {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Service = "Container Registry"
    Purpose = "Test Container Storage"
  })
}

# Azure Key Vault for storing pipeline secrets and service connection credentials
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  
  # Enable soft delete and purge protection for production
  soft_delete_retention_days = var.environment == "production" ? 90 : 7
  purge_protection_enabled   = var.delete_protection
  
  # Network access configuration
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = merge(local.common_tags, {
    Service = "Key Vault"
    Purpose = "Pipeline Secrets"
  })
}

# Key Vault access policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "ManageContacts", "ManageIssuers"
  ]
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Encrypt", "Decrypt", "Sign", "Verify"
  ]
}

# Log Analytics Workspace for monitoring and logging
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "${local.resource_prefix}-law-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "production" ? 90 : 30
  
  tags = merge(local.common_tags, {
    Service = "Log Analytics"
    Purpose = "Monitoring and Logging"
  })
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "${local.resource_prefix}-ai-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  
  tags = merge(local.common_tags, {
    Service = "Application Insights"
    Purpose = "Test Performance Monitoring"
  })
}

# Azure DevOps Project
resource "azuredevops_project" "main" {
  name               = var.azuredevops_project_name
  description        = var.azuredevops_project_description
  visibility         = var.azuredevops_project_visibility
  version_control    = var.azuredevops_project_version_control
  work_item_template = var.azuredevops_project_work_item_template
  
  features = {
    "boards"       = "enabled"
    "repositories" = "enabled"
    "pipelines"    = "enabled"
    "testplans"    = "enabled"
    "artifacts"    = "enabled"
  }
}

# Azure DevOps Git Repository
resource "azuredevops_git_repository" "main" {
  project_id = azuredevops_project.main.id
  name       = var.azuredevops_project_name
  
  initialization {
    init_type = "Clean"
  }
}

# Service connection for Azure Resource Manager
resource "azuredevops_serviceendpoint_azurerm" "main" {
  project_id                             = azuredevops_project.main.id
  service_endpoint_name                  = "Azure-Playwright-Connection"
  description                            = "Service connection for Azure Playwright Testing resources"
  service_endpoint_authentication_scheme = "ServicePrincipal"
  
  credentials {
    serviceprincipalid  = data.azurerm_client_config.current.client_id
    serviceprincipalkey = "placeholder" # This should be configured separately
  }
  
  azurerm_spn_tenantid      = data.azurerm_client_config.current.tenant_id
  azurerm_subscription_id   = data.azurerm_subscription.current.subscription_id
  azurerm_subscription_name = data.azurerm_subscription.current.display_name
}

# Service connection for Azure Container Registry
resource "azuredevops_serviceendpoint_dockerregistry" "acr" {
  project_id            = azuredevops_project.main.id
  service_endpoint_name = "ACR-Connection"
  description           = "Service connection for Azure Container Registry"
  docker_registry       = "https://${azurerm_container_registry.main.login_server}"
  docker_username       = azurerm_container_registry.main.admin_username
  docker_password       = azurerm_container_registry.main.admin_password
  registry_type         = "DockerHub"
}

# Azure DevOps Variable Group for pipeline configuration
resource "azuredevops_variable_group" "pipeline_vars" {
  project_id   = azuredevops_project.main.id
  name         = "Playwright-Pipeline-Variables"
  description  = "Variables for Playwright testing pipeline"
  allow_access = true
  
  variable {
    name  = "ContainerRegistryName"
    value = azurerm_container_registry.main.name
  }
  
  variable {
    name  = "ContainerRegistryServer"
    value = azurerm_container_registry.main.login_server
  }
  
  variable {
    name  = "ResourceGroupName"
    value = azurerm_resource_group.main.name
  }
  
  variable {
    name  = "NodeVersion"
    value = var.node_version
  }
  
  variable {
    name         = "NotificationEmail"
    value        = var.notification_email
    is_secret    = false
    content_type = ""
  }
  
  # Application Insights instrumentation key (if monitoring is enabled)
  dynamic "variable" {
    for_each = var.enable_monitoring ? [1] : []
    content {
      name  = "ApplicationInsightsKey"
      value = azurerm_application_insights.main[0].instrumentation_key
    }
  }
}

# Key Vault secrets for sensitive pipeline variables
resource "azurerm_key_vault_secret" "acr_username" {
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  name         = "acr-username"
  value        = azurerm_container_registry.main.admin_username
  key_vault_id = azurerm_key_vault.main.id
  
  tags = {
    Purpose = "Pipeline Authentication"
  }
}

resource "azurerm_key_vault_secret" "acr_password" {
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  name         = "acr-password"
  value        = azurerm_container_registry.main.admin_password
  key_vault_id = azurerm_key_vault.main.id
  
  tags = {
    Purpose = "Pipeline Authentication"
  }
}

# Wait for project creation before creating pipeline
resource "time_sleep" "wait_for_project" {
  depends_on = [azuredevops_project.main]
  
  create_duration = "30s"
}

# Azure DevOps Build Pipeline
resource "azuredevops_build_definition" "main" {
  depends_on = [time_sleep.wait_for_project]
  
  project_id = azuredevops_project.main.id
  name       = var.pipeline_name
  path       = "\\Playwright Testing"
  
  ci_trigger {
    use_yaml = true
  }
  
  pull_request_trigger {
    use_yaml = true
  }
  
  repository {
    repo_type   = "TfsGit"
    repo_id     = azuredevops_git_repository.main.id
    branch_name = var.pipeline_branch
    yml_path    = var.pipeline_yaml_path
  }
  
  variable_groups = [
    azuredevops_variable_group.pipeline_vars.id
  ]
  
  variable {
    name  = "vmImage"
    value = "ubuntu-latest"
  }
  
  variable {
    name  = "buildConfiguration"
    value = "Release"
  }
  
  # Pipeline-specific variables for Playwright testing
  variable {
    name  = "PlaywrightBrowsers"
    value = join(",", var.playwright_browsers)
  }
  
  variable {
    name  = "TestTimeout"
    value = "30000"
  }
  
  variable {
    name  = "RetryCount"
    value = "2"
  }
}

# Azure DevOps Pipeline permissions for service connections
resource "azuredevops_pipeline_authorization" "azure_connection" {
  project_id  = azuredevops_project.main.id
  resource_id = azuredevops_serviceendpoint_azurerm.main.id
  type        = "endpoint"
  pipeline_id = azuredevops_build_definition.main.id
}

resource "azuredevops_pipeline_authorization" "acr_connection" {
  project_id  = azuredevops_project.main.id
  resource_id = azuredevops_serviceendpoint_dockerregistry.acr.id
  type        = "endpoint"
  pipeline_id = azuredevops_build_definition.main.id
}

# Create test result dashboard (using Azure DevOps dashboard API)
resource "azuredevops_dashboard" "test_dashboard" {
  depends_on = [azuredevops_build_definition.main]
  
  project_id = azuredevops_project.main.id
  name       = "Playwright Test Dashboard"
  
  widget {
    name = "Test Results Trend"
    type = "ms.vss-test-web.test-results-trend-widget"
    size = "1x1"
    position {
      row    = 1
      column = 1
    }
  }
  
  widget {
    name = "Build Summary"
    type = "ms.vss-build-web.build-summary-widget"
    size = "1x1"
    position {
      row    = 1
      column = 2
    }
  }
  
  widget {
    name = "Test Duration"
    type = "ms.vss-test-web.test-duration-widget"
    size = "1x1"
    position {
      row    = 2
      column = 1
    }
  }
}

# Azure Monitor Alert Rule for test failures (if monitoring is enabled)
resource "azurerm_monitor_action_group" "test_alerts" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  name                = "${local.resource_prefix}-test-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "testalerts"
  
  email_receiver {
    name          = "Test Team"
    email_address = var.notification_email
  }
  
  tags = local.common_tags
}

# Custom role definition for Playwright Testing service
resource "azurerm_role_definition" "playwright_testing" {
  name        = "Playwright Testing Service Role"
  scope       = azurerm_resource_group.main.id
  description = "Custom role for Azure Playwright Testing service operations"
  
  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Storage/storageAccounts/write",
      "Microsoft.Storage/storageAccounts/listkeys/action",
      "Microsoft.ContainerRegistry/registries/read",
      "Microsoft.ContainerRegistry/registries/pull/read",
      "Microsoft.ContainerRegistry/registries/push/write"
    ]
    
    not_actions = []
    
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete"
    ]
    
    not_data_actions = []
  }
}

# Storage Account for test artifacts and reports
resource "azurerm_storage_account" "test_artifacts" {
  name                     = "st${local.random_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "production" ? "GRS" : "LRS"
  
  # Enable advanced security features
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  blob_properties {
    cors_rule {
      allowed_origins    = ["*"]
      allowed_methods    = ["GET", "POST"]
      allowed_headers    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
    
    delete_retention_policy {
      days = var.environment == "production" ? 30 : 7
    }
    
    container_delete_retention_policy {
      days = var.environment == "production" ? 30 : 7
    }
    
    versioning_enabled = true
  }
  
  tags = merge(local.common_tags, {
    Service = "Storage"
    Purpose = "Test Artifacts"
  })
}

# Storage container for test reports
resource "azurerm_storage_container" "test_reports" {
  name                  = "test-reports"
  storage_account_name  = azurerm_storage_account.test_artifacts.name
  container_access_type = "private"
}

# Storage container for test screenshots and videos
resource "azurerm_storage_container" "test_media" {
  name                  = "test-media"
  storage_account_name  = azurerm_storage_account.test_artifacts.name
  container_access_type = "private"
}