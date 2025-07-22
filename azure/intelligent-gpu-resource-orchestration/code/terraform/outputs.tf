# Outputs for Azure GPU orchestration infrastructure
# These outputs provide essential information for verification, integration, and operational management

# ============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# ============================================================================

output "resource_group" {
  description = "Resource group information for the GPU orchestration infrastructure"
  value = {
    name     = azurerm_resource_group.main.name
    location = azurerm_resource_group.main.location
    id       = azurerm_resource_group.main.id
  }
}

output "unique_suffix" {
  description = "Unique suffix used for resource naming"
  value       = random_string.suffix.result
}

# ============================================================================
# CONTAINER APPS OUTPUTS
# ============================================================================

output "container_apps" {
  description = "Azure Container Apps configuration and endpoints"
  value = {
    environment_name = azurerm_container_app_environment.main.name
    environment_id   = azurerm_container_app_environment.main.id
    app_name         = azurerm_container_app.ml_inference.name
    app_id           = azurerm_container_app.ml_inference.id
    fqdn             = azurerm_container_app.ml_inference.latest_revision_fqdn
    ingress_url      = "https://${azurerm_container_app.ml_inference.latest_revision_fqdn}"
    min_replicas     = var.aca_min_replicas
    max_replicas     = var.aca_max_replicas
    cpu_cores        = var.aca_cpu_cores
    memory_gi        = var.aca_memory_gi
  }
  
  sensitive = false
}

# ============================================================================
# AZURE BATCH OUTPUTS
# ============================================================================

output "batch_service" {
  description = "Azure Batch account and pool configuration"
  value = {
    account_name              = azurerm_batch_account.main.name
    account_id                = azurerm_batch_account.main.id
    account_endpoint          = azurerm_batch_account.main.account_endpoint
    pool_name                 = azurerm_batch_pool.gpu_pool.name
    pool_id                   = azurerm_batch_pool.gpu_pool.id
    vm_size                   = var.batch_vm_size
    max_dedicated_nodes       = var.batch_max_dedicated_nodes
    max_low_priority_nodes    = var.batch_max_low_priority_nodes
    target_low_priority_nodes = var.batch_target_low_priority_nodes
    auto_scale_enabled        = true
  }
  
  sensitive = false
}

# ============================================================================
# FUNCTION APP OUTPUTS
# ============================================================================

output "function_app" {
  description = "Azure Function App configuration for request routing"
  value = {
    name             = azurerm_linux_function_app.router.name
    id               = azurerm_linux_function_app.router.id
    default_hostname = azurerm_linux_function_app.router.default_hostname
    function_url     = "https://${azurerm_linux_function_app.router.default_hostname}"
    runtime          = var.function_app_runtime
    runtime_version  = var.function_app_runtime_version
    managed_identity = {
      principal_id = azurerm_linux_function_app.router.identity[0].principal_id
      tenant_id    = azurerm_linux_function_app.router.identity[0].tenant_id
    }
  }
  
  sensitive = false
}

# ============================================================================
# STORAGE OUTPUTS
# ============================================================================

output "storage" {
  description = "Storage account and queue configuration"
  value = {
    account_name                = azurerm_storage_account.main.name
    account_id                  = azurerm_storage_account.main.id
    batch_inference_queue_name  = azurerm_storage_queue.batch_inference.name
    batch_inference_dlq_name    = azurerm_storage_queue.batch_inference_dlq.name
    primary_blob_endpoint       = azurerm_storage_account.main.primary_blob_endpoint
    primary_queue_endpoint      = azurerm_storage_account.main.primary_queue_endpoint
    tier                        = var.storage_account_tier
    replication_type           = var.storage_account_replication_type
  }
  
  sensitive = false
}

# ============================================================================
# KEY VAULT OUTPUTS
# ============================================================================

output "key_vault" {
  description = "Key Vault configuration for secure parameter management"
  value = {
    name         = azurerm_key_vault.main.name
    id           = azurerm_key_vault.main.id
    vault_uri    = azurerm_key_vault.main.vault_uri
    tenant_id    = azurerm_key_vault.main.tenant_id
    sku_name     = azurerm_key_vault.main.sku_name
    secret_names = [
      azurerm_key_vault_secret.storage_connection_string.name,
      azurerm_key_vault_secret.realtime_threshold_ms.name,
      azurerm_key_vault_secret.batch_cost_threshold.name,
      azurerm_key_vault_secret.max_aca_replicas.name,
      azurerm_key_vault_secret.max_batch_nodes.name,
      azurerm_key_vault_secret.model_version.name,
      azurerm_key_vault_secret.gpu_memory_limit.name
    ]
  }
  
  sensitive = false
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "monitoring" {
  description = "Azure Monitor and Application Insights configuration"
  value = {
    log_analytics_workspace = {
      name         = azurerm_log_analytics_workspace.main.name
      id           = azurerm_log_analytics_workspace.main.id
      workspace_id = azurerm_log_analytics_workspace.main.workspace_id
      sku          = azurerm_log_analytics_workspace.main.sku
      retention_days = azurerm_log_analytics_workspace.main.retention_in_days
    }
    application_insights = {
      name                 = azurerm_application_insights.main.name
      id                   = azurerm_application_insights.main.id
      instrumentation_key  = azurerm_application_insights.main.instrumentation_key
      connection_string    = azurerm_application_insights.main.connection_string
      application_type     = azurerm_application_insights.main.application_type
    }
    alerts_enabled = var.enable_monitoring_alerts
  }
  
  # Connection string contains sensitive data
  sensitive = true
}

# ============================================================================
# CONFIGURATION PARAMETERS OUTPUTS
# ============================================================================

output "configuration" {
  description = "Configuration parameters for GPU orchestration"
  value = {
    realtime_threshold_ms      = var.realtime_threshold_ms
    batch_cost_threshold       = var.batch_cost_threshold
    model_version             = var.model_version
    gpu_memory_limit_mb       = var.gpu_memory_limit_mb
    gpu_utilization_threshold = var.gpu_utilization_alert_threshold
    queue_depth_threshold     = var.batch_queue_depth_alert_threshold
    cost_alert_threshold      = var.cost_alert_threshold
  }
  
  sensitive = false
}

# ============================================================================
# OPERATIONAL ENDPOINTS
# ============================================================================

output "endpoints" {
  description = "Key endpoints for accessing and managing the GPU orchestration system"
  value = {
    ml_inference_api      = "https://${azurerm_container_app.ml_inference.latest_revision_fqdn}"
    router_function_api   = "https://${azurerm_linux_function_app.router.default_hostname}"
    key_vault_url        = azurerm_key_vault.main.vault_uri
    batch_account_url    = azurerm_batch_account.main.account_endpoint
    storage_queue_url    = azurerm_storage_account.main.primary_queue_endpoint
    log_analytics_portal = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
  }
  
  sensitive = false
}

# ============================================================================
# COST ESTIMATION OUTPUTS
# ============================================================================

output "cost_estimation" {
  description = "Estimated daily costs for GPU resources (USD, approximate)"
  value = {
    container_apps_serverless_gpu = "Variable, ~$0.526/hour per T4 GPU when active"
    batch_low_priority_vms       = "~$0.336/hour per Standard_NC6s_v3 low-priority VM"
    batch_dedicated_vms          = "~$1.68/hour per Standard_NC6s_v3 dedicated VM"
    function_app_consumption     = "~$0.20/million executions + $0.000016/GB-s"
    storage_account             = "~$0.05/month for standard LRS"
    key_vault                   = "~$0.03/10,000 operations"
    log_analytics               = "~$2.30/GB ingested"
    estimated_daily_minimum     = "$2-5 (with minimal usage)"
    estimated_daily_typical     = "$20-50 (with moderate GPU usage)"
    estimated_daily_maximum     = "$200+ (with high GPU utilization)"
  }
  
  sensitive = false
}

# ============================================================================
# DEPLOYMENT VERIFICATION OUTPUTS
# ============================================================================

output "deployment_verification" {
  description = "Commands and URLs for verifying successful deployment"
  value = {
    test_container_app = "curl -X GET https://${azurerm_container_app.ml_inference.latest_revision_fqdn}/"
    check_batch_pool = "az batch pool show --pool-id ${azurerm_batch_pool.gpu_pool.name} --account-name ${azurerm_batch_account.main.name}"
    test_storage_queue = "az storage message put --queue-name ${azurerm_storage_queue.batch_inference.name} --content 'test-message' --account-name ${azurerm_storage_account.main.name}"
    check_key_vault = "az keyvault secret show --vault-name ${azurerm_key_vault.main.name} --name ${azurerm_key_vault_secret.realtime_threshold_ms.name}"
    view_logs = "az monitor log-analytics workspace show --resource-group ${azurerm_resource_group.main.name} --workspace-name ${azurerm_log_analytics_workspace.main.name}"
  }
  
  sensitive = false
}

# ============================================================================
# TERRAFORM STATE OUTPUTS
# ============================================================================

output "terraform_state" {
  description = "Terraform state information for infrastructure management"
  value = {
    resource_count    = length([
      azurerm_resource_group.main,
      azurerm_storage_account.main,
      azurerm_key_vault.main,
      azurerm_log_analytics_workspace.main,
      azurerm_application_insights.main,
      azurerm_batch_account.main,
      azurerm_batch_pool.gpu_pool,
      azurerm_container_app_environment.main,
      azurerm_container_app.ml_inference,
      azurerm_service_plan.function_app,
      azurerm_linux_function_app.router
    ])
    deployment_time   = timestamp()
    terraform_version = "~> 1.0"
    provider_versions = {
      azurerm = "~> 3.110"
      azuread = "~> 2.53"
      random  = "~> 3.6"
    }
  }
  
  sensitive = false
}