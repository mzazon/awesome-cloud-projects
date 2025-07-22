# Azure Compute Fleet and Batch Cost-Efficient Processing Infrastructure

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  
  # Resource names with consistent naming convention
  resource_group_name  = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  storage_account_name = "st${replace(var.project_name, "-", "")}${local.resource_suffix}"
  batch_account_name   = "batch${replace(var.project_name, "-", "")}${local.resource_suffix}"
  compute_fleet_name   = "fleet-${var.project_name}-${local.resource_suffix}"
  log_workspace_name   = "log-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Common tags to be applied to all resources
  common_tags = merge(var.tags, {
    ResourceSuffix = local.resource_suffix
    Location       = var.location
    CreatedBy      = "terraform"
    CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "batch_fleet" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Storage Account for Batch processing data
resource "azurerm_storage_account" "batch_storage" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.batch_fleet.name
  location            = azurerm_resource_group.batch_fleet.location
  
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  allow_nested_items_to_be_public = false
  enable_https_traffic_only       = true
  min_tls_version                 = "TLS1_2"
  
  # Blob properties for cost optimization
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
    
    versioning_enabled = false
    
    # Enable lifecycle management for cost optimization
    lifecycle_rule {
      name    = "batch-data-lifecycle"
      enabled = true
      
      blob_snapshot {
        delete_after_days = 7
      }
      
      base_blob {
        tier_to_cool_after_days    = 30
        tier_to_archive_after_days = 90
        delete_after_days          = 365
      }
    }
  }
  
  tags = local.common_tags
}

# Storage containers for batch processing
resource "azurerm_storage_container" "batch_input" {
  name                  = "batch-input"
  storage_account_name  = azurerm_storage_account.batch_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "batch_output" {
  name                  = "batch-output"
  storage_account_name  = azurerm_storage_account.batch_storage.name
  container_access_type = "private"
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "batch_monitoring" {
  name                = local.log_workspace_name
  resource_group_name = azurerm_resource_group.batch_fleet.name
  location            = azurerm_resource_group.batch_fleet.location
  
  sku               = "PerGB2018"
  retention_in_days = var.log_analytics_retention_days
  
  tags = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "batch_insights" {
  name                = "appi-${var.project_name}-${var.environment}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.batch_fleet.name
  location            = azurerm_resource_group.batch_fleet.location
  
  workspace_id     = azurerm_log_analytics_workspace.batch_monitoring.id
  application_type = "other"
  
  tags = local.common_tags
}

# Azure Batch Account
resource "azurerm_batch_account" "batch_processing" {
  name                = local.batch_account_name
  resource_group_name = azurerm_resource_group.batch_fleet.name
  location            = azurerm_resource_group.batch_fleet.location
  
  # Link to storage account for automatic storage management
  storage_account_id           = azurerm_storage_account.batch_storage.id
  storage_account_authentication_mode = "StorageKeys"
  
  # Pool allocation mode for cost efficiency
  pool_allocation_mode = "BatchService"
  
  # Public network access configuration
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# Azure Batch Pool for cost-efficient processing
resource "azurerm_batch_pool" "cost_efficient_pool" {
  name                = "batch-pool-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.batch_fleet.name
  account_name        = azurerm_batch_account.batch_processing.name
  
  # VM configuration for Windows Server
  vm_size = var.batch_pool_vm_size
  
  # Node configuration
  target_dedicated_nodes   = var.batch_pool_target_dedicated_nodes
  target_low_priority_nodes = var.batch_pool_target_low_priority_nodes
  
  # Display name for the pool
  display_name = "Cost-Efficient Batch Pool"
  
  # Auto-scaling configuration
  auto_scale {
    evaluation_interval = "PT5M"
    formula = <<-EOT
      // Auto-scale formula for cost-efficient processing
      // Scale based on pending tasks with cost optimization
      $TargetLowPriorityNodes = min(${var.batch_pool_max_nodes}, max(0, $PendingTasks.GetSample(1 * TimeInterval_Minute, 0).GetAverage() * 2));
      $TargetDedicatedNodes = min(${var.batch_pool_target_dedicated_nodes}, max(0, $ActiveTasks.GetSample(1 * TimeInterval_Minute, 0).GetAverage()));
      $NodeDeallocationOption = taskcompletion;
    EOT
  }
  
  # VM configuration
  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-core"
    version   = "latest"
  }
  
  # Node agent configuration
  node_agent_sku_id = "batch.node.windows amd64"
  
  # Start task for node initialization
  start_task {
    command_line         = "cmd /c echo 'Batch node ready for cost-efficient processing' && timeout /t 30"
    wait_for_success    = true
    user_identity {
      auto_user {
        elevation_level = "Admin"
        scope          = "Pool"
      }
    }
  }
  
  # User accounts for task execution
  user_accounts {
    name     = var.admin_username
    password = var.admin_password
    
    elevation_level = "Admin"
    
    # Windows-specific user configuration
    windows_user_configuration {
      login_mode = "Interactive"
    }
  }
  
  # Network configuration for security
  network_configuration {
    # Enable accelerated networking if supported
    dynamic "endpoint_configuration" {
      for_each = []
      content {
        name                 = endpoint_configuration.value.name
        protocol            = endpoint_configuration.value.protocol
        backend_port        = endpoint_configuration.value.backend_port
        frontend_port_range = endpoint_configuration.value.frontend_port_range
        
        network_security_group_rules {
          priority               = endpoint_configuration.value.priority
          access                = endpoint_configuration.value.access
          source_address_prefix = endpoint_configuration.value.source_address_prefix
        }
      }
    }
  }
  
  # Metadata for cost tracking
  metadata = {
    purpose            = "cost-efficient-batch-processing"
    spot_usage_enabled = "true"
    auto_scale_enabled = "true"
  }
}

# Note: Azure Compute Fleet is a newer service that may not be fully supported in the current azurerm provider
# For production deployments, consider using Azure ARM templates or REST API calls
# The configuration below represents the intended Compute Fleet setup

# Diagnostic settings for Batch Account monitoring
resource "azurerm_monitor_diagnostic_setting" "batch_diagnostics" {
  name                       = "batch-diagnostics"
  target_resource_id         = azurerm_batch_account.batch_processing.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.batch_monitoring.id
  
  # Enable service logs
  enabled_log {
    category = "ServiceLog"
    
    retention_policy {
      enabled = true
      days    = 7
    }
  }
  
  # Enable all metrics
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 7
    }
  }
}

# Action Group for cost alerts
resource "azurerm_monitor_action_group" "cost_alerts" {
  name                = "cost-alerts-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.batch_fleet.name
  short_name          = "costalerts"
  
  email_receiver {
    name          = "cost-admin"
    email_address = var.notification_email
  }
  
  tags = local.common_tags
}

# Metric Alert for high CPU usage (cost optimization indicator)
resource "azurerm_monitor_metric_alert" "high_cpu_usage" {
  name                = "batch-high-cpu-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.batch_fleet.name
  scopes              = [azurerm_batch_account.batch_processing.id]
  
  description   = "Alert when batch processing CPU usage exceeds threshold"
  severity      = 2
  frequency     = "PT5M"
  window_size   = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.Batch/batchAccounts"
    metric_name      = "CoreCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.cost_alerts.id
  }
  
  tags = local.common_tags
}

# Scheduled Query Rule for cost monitoring
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "cost_monitoring" {
  name                = "batch-cost-monitoring-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.batch_fleet.name
  location            = azurerm_resource_group.batch_fleet.location
  
  evaluation_frequency = "PT15M"
  window_duration     = "PT15M"
  scopes              = [azurerm_log_analytics_workspace.batch_monitoring.id]
  severity            = 2
  
  description = "Monitor batch processing costs and resource utilization"
  
  criteria {
    query                   = <<-QUERY
      Usage
      | where TimeGenerated > ago(1h)
      | where IsBillable == true
      | summarize TotalCost = sum(Quantity) by bin(TimeGenerated, 15m)
      | where TotalCost > 10
    QUERY
    time_aggregation_method = "Average"
    threshold              = 1.0
    operator               = "GreaterThan"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
  
  action {
    action_groups = [azurerm_monitor_action_group.cost_alerts.id]
  }
  
  tags = local.common_tags
}

# Role assignment for Batch Service to access storage
resource "azurerm_role_assignment" "batch_storage_access" {
  scope                = azurerm_storage_account.batch_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_batch_account.batch_processing.identity[0].principal_id
}

# Output values for other configurations or external integrations
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.batch_fleet.name
}

output "storage_account_name" {
  description = "Name of the storage account for batch processing"
  value       = azurerm_storage_account.batch_storage.name
}

output "batch_account_name" {
  description = "Name of the Azure Batch account"
  value       = azurerm_batch_account.batch_processing.name
}

output "batch_pool_id" {
  description = "ID of the created batch pool"
  value       = azurerm_batch_pool.cost_efficient_pool.id
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.batch_monitoring.id
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.batch_insights.instrumentation_key
  sensitive   = true
}

output "batch_account_endpoint" {
  description = "Azure Batch account endpoint"
  value       = azurerm_batch_account.batch_processing.account_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.batch_storage.primary_connection_string
  sensitive   = true
}