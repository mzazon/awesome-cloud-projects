# Main Terraform configuration for Azure GPU orchestration infrastructure
# This creates a complete solution for dynamic GPU resource allocation between
# Azure Container Apps serverless GPUs and Azure Batch GPU pools

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for consistent naming and configuration
locals {
  name_suffix = random_string.suffix.result
  
  # Consolidated tags for all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    CreatedBy   = "Terraform"
    CreatedAt   = timestamp()
  })
  
  # Resource naming convention
  resource_names = {
    resource_group      = var.resource_group_name
    storage_account     = "storage${local.name_suffix}"
    key_vault          = "kv-gpu-${local.name_suffix}"
    log_workspace      = "logs-gpu-${local.name_suffix}"
    aca_environment    = "aca-env-${local.name_suffix}"
    aca_app            = "ml-inference-app"
    batch_account      = "batch${local.name_suffix}"
    batch_pool         = "gpu-pool"
    function_app       = "router-func-${local.name_suffix}"
    app_service_plan   = "asp-${local.name_suffix}"
    app_insights       = "ai-${local.name_suffix}"
  }
}

# ============================================================================
# RESOURCE GROUP
# ============================================================================

# Primary resource group for all GPU orchestration resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_names.resource_group
  location = var.location
  
  tags = local.common_tags
}

# ============================================================================
# LOG ANALYTICS WORKSPACE FOR MONITORING
# ============================================================================

# Log Analytics workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.resource_names.log_workspace
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = local.common_tags
}

# Application Insights for detailed application monitoring
resource "azurerm_application_insights" "main" {
  name                = local.resource_names.app_insights
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  tags = local.common_tags
}

# ============================================================================
# STORAGE ACCOUNT FOR QUEUES AND FUNCTION APP
# ============================================================================

# Storage account for queue storage and Azure Function backend
resource "azurerm_storage_account" "main" {
  name                     = local.resource_names.storage_account
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable secure transfer and disable public access for security
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Blob properties for lifecycle management
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Storage queues for batch job management
resource "azurerm_storage_queue" "batch_inference" {
  name                 = "batch-inference-queue"
  storage_account_name = azurerm_storage_account.main.name
}

# Dead letter queue for failed batch jobs
resource "azurerm_storage_queue" "batch_inference_dlq" {
  name                 = "batch-inference-dlq"
  storage_account_name = azurerm_storage_account.main.name
}

# ============================================================================
# KEY VAULT FOR SECURE CONFIGURATION MANAGEMENT
# ============================================================================

# Key Vault for secure storage of configuration parameters and secrets
resource "azurerm_key_vault" "main" {
  name                = local.resource_names.key_vault
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Enable RBAC authorization instead of access policies
  enable_rbac_authorization = true
  
  # Security settings
  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  purge_protection_enabled        = false
  soft_delete_retention_days      = 7
  
  # Network access restrictions
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = local.common_tags
}

# Key Vault Secrets Officer role assignment for current user
resource "azurerm_role_assignment" "key_vault_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Configuration parameters stored in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
  
  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "realtime_threshold_ms" {
  name         = "realtime-threshold-ms"
  value        = tostring(var.realtime_threshold_ms)
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
  
  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "batch_cost_threshold" {
  name         = "batch-cost-threshold"
  value        = tostring(var.batch_cost_threshold)
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
  
  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "max_aca_replicas" {
  name         = "max-aca-replicas"
  value        = tostring(var.aca_max_replicas)
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
  
  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "max_batch_nodes" {
  name         = "max-batch-nodes"
  value        = tostring(var.batch_max_low_priority_nodes)
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
  
  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "model_version" {
  name         = "model-version"
  value        = var.model_version
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
  
  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "gpu_memory_limit" {
  name         = "gpu-memory-limit"
  value        = tostring(var.gpu_memory_limit_mb)
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
  
  tags = local.common_tags
}

# ============================================================================
# AZURE BATCH ACCOUNT AND GPU POOL
# ============================================================================

# Azure Batch account for GPU batch processing
resource "azurerm_batch_account" "main" {
  name                                = local.resource_names.batch_account
  resource_group_name                 = azurerm_resource_group.main.name
  location                           = azurerm_resource_group.main.location
  pool_allocation_mode               = "BatchService"
  storage_account_id                 = azurerm_storage_account.main.id
  storage_account_authentication_mode = "StorageKeys"
  
  tags = local.common_tags
}

# Azure Batch pool with GPU VMs for cost-optimized batch processing
resource "azurerm_batch_pool" "gpu_pool" {
  name                = local.resource_names.batch_pool
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_batch_account.main.name
  display_name        = "GPU Processing Pool"
  vm_size             = var.batch_vm_size
  node_agent_sku_id   = "batch.node.ubuntu 20.04"
  
  # Auto-scaling configuration for cost optimization
  auto_scale {
    evaluation_interval = "PT5M"
    formula = join("", [
      "$TargetDedicatedNodes = min($PendingTasks.GetSample(180 * TimeInterval_Second, 70 * TimeInterval_Second), ${var.batch_max_dedicated_nodes});",
      "$TargetLowPriorityNodes = min($PendingTasks.GetSample(180 * TimeInterval_Second, 70 * TimeInterval_Second), ${var.batch_max_low_priority_nodes});"
    ])
  }
  
  # Fixed scale configuration (used when auto_scale is not enabled)
  fixed_scale {
    target_dedicated_nodes   = 0
    target_low_priority_nodes = var.batch_target_low_priority_nodes
  }
  
  # VM configuration with Ubuntu container support
  storage_image_reference {
    publisher = "microsoft-azure-batch"
    offer     = "ubuntu-server-container"
    sku       = "20-04-lts"
    version   = "latest"
  }
  
  # Network configuration
  inter_node_communication = "Disabled"
  max_tasks_per_node       = 1
  
  # Start task for node initialization
  start_task {
    command_line         = "apt-get update && apt-get install -y python3-pip && pip3 install azure-storage-queue torch torchvision"
    wait_for_success     = true
    max_task_retry_count = 3
    
    user_identity {
      auto_user {
        elevation_level = "Admin"
        scope          = "Pool"
      }
    }
  }
  
  tags = local.common_tags
}

# ============================================================================
# AZURE CONTAINER APPS ENVIRONMENT AND APPLICATION
# ============================================================================

# Container Apps environment with GPU support
resource "azurerm_container_app_environment" "main" {
  name                       = local.resource_names.aca_environment
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  tags = local.common_tags
}

# Container App for ML inference with GPU acceleration
resource "azurerm_container_app" "ml_inference" {
  name                         = local.resource_names.aca_app
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  
  # Template configuration for the container app
  template {
    min_replicas = var.aca_min_replicas
    max_replicas = var.aca_max_replicas
    
    # Container configuration
    container {
      name   = local.resource_names.aca_app
      image  = var.container_image
      cpu    = var.aca_cpu_cores
      memory = var.aca_memory_gi
      
      # Environment variables for ML inference
      env {
        name  = "MODEL_PATH"
        value = "/models"
      }
      
      env {
        name  = "GPU_ENABLED"
        value = "true"
      }
      
      env {
        name        = "KEY_VAULT_URL"
        secret_name = "key-vault-url"
      }
    }
    
    # HTTP scaling rules based on request volume
    http_scale_rule {
      name                = "http-scaler"
      concurrent_requests = "10"
    }
  }
  
  # Ingress configuration for external access
  ingress {
    external_enabled = true
    target_port      = 80
    
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  
  # Secret configuration for Key Vault access
  secret {
    name  = "key-vault-url"
    value = azurerm_key_vault.main.vault_uri
  }
  
  tags = local.common_tags
}

# ============================================================================
# AZURE FUNCTION APP FOR REQUEST ROUTING
# ============================================================================

# App Service Plan for Azure Function App
resource "azurerm_service_plan" "function_app" {
  name                = local.resource_names.app_service_plan
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  os_type            = "Linux"
  sku_name           = "Y1"  # Consumption plan for serverless execution
  
  tags = local.common_tags
}

# Azure Function App for intelligent request routing
resource "azurerm_linux_function_app" "router" {
  name                = local.resource_names.function_app
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id           = azurerm_service_plan.function_app.id
  
  # Function runtime configuration
  site_config {
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # Application Insights integration
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }
  
  # Application settings for function configuration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"        = var.function_app_runtime
    "KEY_VAULT_URL"                  = azurerm_key_vault.main.vault_uri
    "ACA_ENDPOINT"                   = "https://${azurerm_container_app.ml_inference.latest_revision_fqdn}"
    "BATCH_ACCOUNT_NAME"             = azurerm_batch_account.main.name
    "BATCH_POOL_ID"                  = azurerm_batch_pool.gpu_pool.name
    "STORAGE_QUEUE_NAME"             = azurerm_storage_queue.batch_inference.name
    "LOG_ANALYTICS_WORKSPACE_ID"     = azurerm_log_analytics_workspace.main.workspace_id
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
  }
  
  # Managed identity for secure access to Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Role assignments for Function App managed identity
resource "azurerm_role_assignment" "function_key_vault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.router.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_batch_contributor" {
  scope                = azurerm_batch_account.main.id
  role_definition_name = "Batch Contributor"
  principal_id         = azurerm_linux_function_app.router.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_storage_queue_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.router.identity[0].principal_id
}

# ============================================================================
# AZURE MONITOR ALERTS FOR GPU OPTIMIZATION
# ============================================================================

# Action group for alert notifications
resource "azurerm_monitor_action_group" "gpu_alerts" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "gpu-orchestration-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "gpualerts"
  
  tags = local.common_tags
}

# Alert for high GPU utilization in Container Apps
resource "azurerm_monitor_metric_alert" "high_gpu_utilization" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "HighGPUUtilization"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.ml_inference.id]
  description         = "High GPU utilization detected in Container Apps"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Requests"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.gpu_utilization_alert_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.gpu_alerts[0].id
  }
  
  tags = local.common_tags
}

# Alert for high batch queue depth
resource "azurerm_monitor_metric_alert" "high_batch_queue_depth" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "HighBatchQueueDepth"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_storage_account.main.id]
  description         = "High batch queue depth detected"
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts/queueServices"
    metric_name      = "QueueMessageCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.batch_queue_depth_alert_threshold
    
    dimension {
      name     = "QueueName"
      operator = "Include"
      values   = [azurerm_storage_queue.batch_inference.name]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.gpu_alerts[0].id
  }
  
  tags = local.common_tags
}

# ============================================================================
# OUTPUTS FOR VERIFICATION AND INTEGRATION
# ============================================================================

# Resource identifiers for verification
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "container_app_fqdn" {
  description = "Fully qualified domain name of the Container App"
  value       = azurerm_container_app.ml_inference.latest_revision_fqdn
}

output "batch_account_name" {
  description = "Name of the Azure Batch account"
  value       = azurerm_batch_account.main.name
}

output "batch_pool_name" {
  description = "Name of the GPU batch pool"
  value       = azurerm_batch_pool.gpu_pool.name
}

output "function_app_name" {
  description = "Name of the router Function App"
  value       = azurerm_linux_function_app.router.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault for configuration access"
  value       = azurerm_key_vault.main.vault_uri
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}