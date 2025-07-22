# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local variables for resource naming
locals {
  suffix                         = random_id.suffix.hex
  resource_group_name           = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${local.suffix}"
  container_env_name            = var.container_env_name != null ? var.container_env_name : "cae-${var.project_name}-${local.suffix}"
  log_analytics_workspace_name  = var.log_analytics_workspace_name != null ? var.log_analytics_workspace_name : "law-${var.project_name}-${local.suffix}"
  storage_account_name          = var.storage_account_name != null ? var.storage_account_name : "st${var.project_name}${local.suffix}"
  load_test_name                = var.load_test_name != null ? var.load_test_name : "lt-${var.project_name}-${local.suffix}"
  
  # Merge default tags with user-provided tags
  tags = merge(var.tags, {
    created_by = "terraform"
    timestamp  = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# Log Analytics Workspace for Container Apps Environment
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.tags
}

# Storage Account for test artifacts and scripts
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  tags = local.tags
}

# Storage containers for test artifacts and scripts
resource "azurerm_storage_container" "load_test_scripts" {
  name                  = "load-test-scripts"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "monitoring_templates" {
  name                  = "monitoring-templates"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                       = local.container_env_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

# Azure Load Testing Resource
resource "azurerm_load_test" "main" {
  name                = local.load_test_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

# Unit Test Job
resource "azurerm_container_app_job" "unit_test" {
  name                         = "unit-test-job"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  container_app_environment_id = azurerm_container_app_environment.main.id
  
  replica_timeout_in_seconds = var.unit_test_job_config.replica_timeout
  replica_retry_limit        = var.unit_test_job_config.replica_retry_limit
  
  manual_trigger_config {
    parallelism              = var.unit_test_job_config.parallelism
    replica_completion_count = 1
  }
  
  template {
    container {
      name   = "unit-test-container"
      image  = var.unit_test_job_config.image
      cpu    = var.unit_test_job_config.cpu
      memory = var.unit_test_job_config.memory
      
      command = ["/bin/bash"]
      args    = ["-c", "echo 'Running unit tests...'; sleep 10; echo 'Unit tests completed successfully'"]
    }
  }
  
  tags = local.tags
}

# Integration Test Job
resource "azurerm_container_app_job" "integration_test" {
  name                         = "integration-test-job"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  container_app_environment_id = azurerm_container_app_environment.main.id
  
  replica_timeout_in_seconds = var.integration_test_job_config.replica_timeout
  replica_retry_limit        = var.integration_test_job_config.replica_retry_limit
  
  manual_trigger_config {
    parallelism              = var.integration_test_job_config.parallelism
    replica_completion_count = 1
  }
  
  template {
    container {
      name   = "integration-test-container"
      image  = var.integration_test_job_config.image
      cpu    = var.integration_test_job_config.cpu
      memory = var.integration_test_job_config.memory
      
      command = ["/bin/bash"]
      args    = ["-c", "echo 'Running integration tests with timeout: $TIMEOUT'; sleep 15; echo 'Integration tests completed'"]
      
      env {
        name  = "TEST_TYPE"
        value = "integration"
      }
      
      env {
        name  = "TIMEOUT"
        value = tostring(var.integration_test_job_config.replica_timeout)
      }
    }
  }
  
  tags = local.tags
}

# Performance Test Job
resource "azurerm_container_app_job" "performance_test" {
  name                         = "performance-test-job"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  container_app_environment_id = azurerm_container_app_environment.main.id
  
  replica_timeout_in_seconds = var.performance_test_job_config.replica_timeout
  replica_retry_limit        = var.performance_test_job_config.replica_retry_limit
  
  manual_trigger_config {
    parallelism              = var.performance_test_job_config.parallelism
    replica_completion_count = 1
  }
  
  template {
    container {
      name   = "performance-test-container"
      image  = var.performance_test_job_config.image
      cpu    = var.performance_test_job_config.cpu
      memory = var.performance_test_job_config.memory
      
      command = ["/bin/bash"]
      args    = ["-c", "echo 'Starting load test orchestration'; echo 'Load test: $LOAD_TEST_NAME'; sleep 30; echo 'Performance test orchestration completed'"]
      
      env {
        name  = "LOAD_TEST_NAME"
        value = azurerm_load_test.main.name
      }
      
      env {
        name  = "RESOURCE_GROUP"
        value = azurerm_resource_group.main.name
      }
    }
  }
  
  tags = local.tags
}

# Security Test Job
resource "azurerm_container_app_job" "security_test" {
  name                         = "security-test-job"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  container_app_environment_id = azurerm_container_app_environment.main.id
  
  replica_timeout_in_seconds = var.security_test_job_config.replica_timeout
  replica_retry_limit        = var.security_test_job_config.replica_retry_limit
  
  manual_trigger_config {
    parallelism              = var.security_test_job_config.parallelism
    replica_completion_count = 1
  }
  
  template {
    container {
      name   = "security-test-container"
      image  = var.security_test_job_config.image
      cpu    = var.security_test_job_config.cpu
      memory = var.security_test_job_config.memory
      
      command = ["/bin/bash"]
      args    = ["-c", "echo 'Starting security scan: $SECURITY_SCAN_TYPE'; sleep 20; echo 'Security scan completed - format: $REPORT_FORMAT'"]
      
      env {
        name  = "SECURITY_SCAN_TYPE"
        value = "full"
      }
      
      env {
        name  = "REPORT_FORMAT"
        value = "json"
      }
    }
  }
  
  tags = local.tags
}

# Application Insights for enhanced monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.tags
}

# Action Group for alerting
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${var.project_name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "qaactiongrp"
  tags                = local.tags
}

# Metric Alert for Container Apps Job failures
resource "azurerm_monitor_metric_alert" "job_failure" {
  name                = "alert-job-failure-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app_environment.main.id]
  description         = "Alert when Container Apps Jobs fail"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.App/jobs"
    metric_name      = "JobExecutionCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
    
    dimension {
      name     = "Status"
      operator = "Include"
      values   = ["Failed"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.tags
}

# Diagnostic settings for Container Apps Environment
resource "azurerm_monitor_diagnostic_setting" "container_apps_env" {
  name                       = "diag-${local.container_env_name}"
  target_resource_id         = azurerm_container_app_environment.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "ContainerAppConsoleLogs"
  }
  
  enabled_log {
    category = "ContainerAppSystemLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}