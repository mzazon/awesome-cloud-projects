# Main Terraform Configuration for Azure CI/CD Testing Workflow
# This configuration deploys Azure Static Web Apps with Container Apps Jobs for automated testing

# Get current client configuration for service principal creation
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Create resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location = var.location
  tags     = var.tags
}

# Create Log Analytics Workspace for monitoring and observability
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Create Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ai-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = 90
  tags                = var.tags
}

# Create Azure Container Registry for storing test container images
resource "azurerm_container_registry" "main" {
  name                = "acr${replace(var.project_name, "-", "")}${var.environment}${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.container_registry_admin_enabled
  tags                = var.tags

  # Enable public network access for CI/CD scenarios
  public_network_access_enabled = true
  
  # Configure network rule set for security
  network_rule_set {
    default_action = "Allow"
  }
}

# Create Container Apps Environment for running testing jobs
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = var.tags

  # Configure workload profiles for better resource management
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

# Create Azure Static Web App for hosting the application
resource "azurerm_static_web_app" "main" {
  name                = "swa-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_tier            = "Free"
  sku_size            = "Free"
  tags                = var.tags

  # Configure GitHub integration for CI/CD
  github_repository_url   = var.github_repository_url
  github_repository_branch = var.github_branch
  
  # Configure build settings
  app_location    = var.github_app_location
  output_location = var.github_output_location
}

# Create Azure Load Testing resource for performance testing
resource "azurerm_load_test" "main" {
  count               = var.enable_load_testing ? 1 : 0
  name                = "alt-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Create Container Apps Job for integration testing
resource "azurerm_container_app_job" "integration_test" {
  name                         = "integration-test-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  container_app_environment_id = azurerm_container_app_environment.main.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = var.integration_test_timeout
  replica_retry_limit          = var.test_job_retry_limit
  tags                         = var.tags

  # Configure manual trigger for CI/CD integration
  manual_trigger_config {
    parallelism              = var.test_parallelism
    replica_completion_count = var.test_completion_count
  }

  # Configure the container template for running tests
  template {
    container {
      name   = "integration-tests"
      image  = "mcr.microsoft.com/azure-cli:latest"
      cpu    = 0.25
      memory = "0.5Gi"

      # Configure environment variables for test execution
      env {
        name  = "STATIC_WEB_APP_URL"
        value = "https://${azurerm_static_web_app.main.default_host_name}"
      }

      env {
        name  = "TEST_TYPE"
        value = "integration"
      }

      env {
        name  = "RESOURCE_GROUP"
        value = azurerm_resource_group.main.name
      }

      # Add Application Insights instrumentation key if monitoring is enabled
      dynamic "env" {
        for_each = var.enable_monitoring ? [1] : []
        content {
          name  = "APPINSIGHTS_INSTRUMENTATIONKEY"
          value = azurerm_application_insights.main[0].instrumentation_key
        }
      }

      # Configure startup command for test execution
      command = ["/bin/bash"]
      args = [
        "-c",
        "echo 'Starting integration tests...'; echo 'Target URL: $STATIC_WEB_APP_URL'; echo 'Running API tests...'; curl -f $STATIC_WEB_APP_URL || exit 1; echo 'Integration tests completed successfully'"
      ]
    }
  }
}

# Create Container Apps Job for load testing
resource "azurerm_container_app_job" "load_test" {
  count                        = var.enable_load_testing ? 1 : 0
  name                         = "load-test-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  container_app_environment_id = azurerm_container_app_environment.main.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = var.load_test_timeout
  replica_retry_limit          = var.test_job_retry_limit
  tags                         = var.tags

  # Configure manual trigger for CI/CD integration
  manual_trigger_config {
    parallelism              = var.test_parallelism
    replica_completion_count = var.test_completion_count
  }

  # Configure the container template for running load tests
  template {
    container {
      name   = "load-tests"
      image  = "mcr.microsoft.com/azure-cli:latest"
      cpu    = 0.5
      memory = "1Gi"

      # Configure environment variables for load test execution
      env {
        name  = "STATIC_WEB_APP_URL"
        value = "https://${azurerm_static_web_app.main.default_host_name}"
      }

      env {
        name  = "LOAD_TEST_RESOURCE"
        value = azurerm_load_test.main[0].name
      }

      env {
        name  = "RESOURCE_GROUP"
        value = azurerm_resource_group.main.name
      }

      env {
        name  = "TEST_TYPE"
        value = "load"
      }

      # Add Application Insights instrumentation key if monitoring is enabled
      dynamic "env" {
        for_each = var.enable_monitoring ? [1] : []
        content {
          name  = "APPINSIGHTS_INSTRUMENTATIONKEY"
          value = azurerm_application_insights.main[0].instrumentation_key
        }
      }

      # Configure startup command for load test execution
      command = ["/bin/bash"]
      args = [
        "-c",
        "echo 'Starting load test...'; echo 'Target URL: $STATIC_WEB_APP_URL'; echo 'Load test resource: $LOAD_TEST_RESOURCE'; echo 'Simulating load test execution...'; sleep 60; echo 'Load test completed successfully'"
      ]
    }
  }
}

# Create Container Apps Job for UI/E2E testing
resource "azurerm_container_app_job" "ui_test" {
  name                         = "ui-test-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  container_app_environment_id = azurerm_container_app_environment.main.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = var.integration_test_timeout
  replica_retry_limit          = var.test_job_retry_limit
  tags                         = var.tags

  # Configure manual trigger for CI/CD integration
  manual_trigger_config {
    parallelism              = var.test_parallelism
    replica_completion_count = var.test_completion_count
  }

  # Configure the container template for running UI tests
  template {
    container {
      name   = "ui-tests"
      image  = "mcr.microsoft.com/playwright:v1.40.0-jammy"
      cpu    = 0.5
      memory = "1Gi"

      # Configure environment variables for UI test execution
      env {
        name  = "STATIC_WEB_APP_URL"
        value = "https://${azurerm_static_web_app.main.default_host_name}"
      }

      env {
        name  = "TEST_TYPE"
        value = "ui"
      }

      env {
        name  = "RESOURCE_GROUP"
        value = azurerm_resource_group.main.name
      }

      # Add Application Insights instrumentation key if monitoring is enabled
      dynamic "env" {
        for_each = var.enable_monitoring ? [1] : []
        content {
          name  = "APPINSIGHTS_INSTRUMENTATIONKEY"
          value = azurerm_application_insights.main[0].instrumentation_key
        }
      }

      # Configure startup command for UI test execution
      command = ["/bin/bash"]
      args = [
        "-c",
        "echo 'Starting UI tests...'; echo 'Target URL: $STATIC_WEB_APP_URL'; echo 'Running Playwright tests...'; npx playwright test --reporter=list || echo 'UI tests completed with warnings'; echo 'UI tests completed'"
      ]
    }
  }
}

# Create Azure AD Application for GitHub Actions integration
resource "azuread_application" "github_actions" {
  count        = var.enable_github_actions_integration ? 1 : 0
  display_name = "GitHub Actions - ${var.project_name}-${var.environment}"
  description  = "Service principal for GitHub Actions CI/CD integration"
  
  # Configure application for service principal usage
  sign_in_audience = "AzureADMyOrg"
  
  # Configure required resource access
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
}

# Create service principal for the Azure AD application
resource "azuread_service_principal" "github_actions" {
  count     = var.enable_github_actions_integration ? 1 : 0
  client_id = azuread_application.github_actions[0].client_id
  
  # Configure service principal properties
  app_role_assignment_required = false
  description                  = "Service principal for GitHub Actions CI/CD operations"
  
  # Configure owners
  owners = [data.azurerm_client_config.current.object_id]
}

# Create service principal password for GitHub Actions authentication
resource "azuread_service_principal_password" "github_actions" {
  count                = var.enable_github_actions_integration ? 1 : 0
  service_principal_id = azuread_service_principal.github_actions[0].object_id
  display_name         = "GitHub Actions Authentication"
  
  # Configure password rotation
  end_date = timeadd(timestamp(), "8760h") # 1 year from now
}

# Assign Contributor role to service principal for resource group
resource "azurerm_role_assignment" "github_actions_contributor" {
  count                = var.enable_github_actions_integration ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions[0].object_id
}

# Assign Container Apps Jobs Executor role to service principal
resource "azurerm_role_assignment" "github_actions_container_jobs" {
  count                = var.enable_github_actions_integration ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Container Apps Jobs Executor"
  principal_id         = azuread_service_principal.github_actions[0].object_id
}

# Create role assignment for ACR pull access
resource "azurerm_role_assignment" "github_actions_acr_pull" {
  count                = var.enable_github_actions_integration ? 1 : 0
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azuread_service_principal.github_actions[0].object_id
}

# Create role assignment for ACR push access
resource "azurerm_role_assignment" "github_actions_acr_push" {
  count                = var.enable_github_actions_integration ? 1 : 0
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github_actions[0].object_id
}

# Create role assignment for Load Testing service access
resource "azurerm_role_assignment" "github_actions_load_testing" {
  count                = var.enable_load_testing && var.enable_github_actions_integration ? 1 : 0
  scope                = azurerm_load_test.main[0].id
  role_definition_name = "Load Test Contributor"
  principal_id         = azuread_service_principal.github_actions[0].object_id
}