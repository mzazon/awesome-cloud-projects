# Outputs for Azure Storage Lifecycle Management Infrastructure
# These outputs provide important information about the created resources
# for integration with other systems and for verification purposes.

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.lifecycle_rg.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.lifecycle_rg.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.lifecycle_rg.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.lifecycle_storage.name
}

output "storage_account_id" {
  description = "ID of the created storage account"
  value       = azurerm_storage_account.lifecycle_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.lifecycle_storage.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.lifecycle_storage.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.lifecycle_storage.primary_access_key
  sensitive   = true
}

output "storage_account_secondary_access_key" {
  description = "Secondary access key for the storage account"
  value       = azurerm_storage_account.lifecycle_storage.secondary_access_key
  sensitive   = true
}

output "storage_account_identity_principal_id" {
  description = "Principal ID of the storage account's managed identity"
  value       = azurerm_storage_account.lifecycle_storage.identity[0].principal_id
}

output "storage_account_identity_tenant_id" {
  description = "Tenant ID of the storage account's managed identity"
  value       = azurerm_storage_account.lifecycle_storage.identity[0].tenant_id
}

# Storage Container Information
output "storage_containers" {
  description = "Information about created storage containers"
  value = {
    for container_name, container in azurerm_storage_container.containers : container_name => {
      name         = container.name
      url          = "https://${azurerm_storage_account.lifecycle_storage.name}.blob.core.windows.net/${container.name}"
      access_type  = container.container_access_type
      has_legal_hold = container.has_legal_hold
    }
  }
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.storage_monitoring.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.storage_monitoring.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.storage_monitoring.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.storage_monitoring.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_secondary_shared_key" {
  description = "Secondary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.storage_monitoring.secondary_shared_key
  sensitive   = true
}

# Monitoring and Alerting Information
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = azurerm_monitor_action_group.storage_alerts.name
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = azurerm_monitor_action_group.storage_alerts.id
}

output "storage_capacity_alert_id" {
  description = "ID of the storage capacity alert"
  value       = var.enable_capacity_alerts ? azurerm_monitor_metric_alert.high_storage_capacity[0].id : null
}

output "transaction_count_alert_id" {
  description = "ID of the transaction count alert"
  value       = var.enable_transaction_alerts ? azurerm_monitor_metric_alert.high_transaction_count[0].id : null
}

output "storage_availability_alert_id" {
  description = "ID of the storage availability alert"
  value       = azurerm_monitor_metric_alert.storage_availability.id
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App for storage alerts"
  value       = var.enable_logic_app_alerts ? azurerm_logic_app_workflow.storage_alerts[0].name : null
}

output "logic_app_id" {
  description = "ID of the Logic App for storage alerts"
  value       = var.enable_logic_app_alerts ? azurerm_logic_app_workflow.storage_alerts[0].id : null
}

output "logic_app_access_endpoint" {
  description = "Access endpoint of the Logic App"
  value       = var.enable_logic_app_alerts ? azurerm_logic_app_workflow.storage_alerts[0].access_endpoint : null
}

output "logic_app_identity_principal_id" {
  description = "Principal ID of the Logic App's managed identity"
  value       = var.enable_logic_app_alerts ? azurerm_logic_app_workflow.storage_alerts[0].identity[0].principal_id : null
}

# Lifecycle Management Policy Information
output "lifecycle_policy_enabled" {
  description = "Whether lifecycle management policy is enabled"
  value       = var.lifecycle_policy_enabled
}

output "lifecycle_policy_id" {
  description = "ID of the lifecycle management policy"
  value       = var.lifecycle_policy_enabled ? azurerm_storage_management_policy.lifecycle_policy[0].id : null
}

output "document_lifecycle_rules" {
  description = "Document lifecycle rules configuration"
  value       = var.document_lifecycle_rules
}

output "log_lifecycle_rules" {
  description = "Log lifecycle rules configuration"
  value       = var.log_lifecycle_rules
}

# Sample Data Information
output "sample_data_created" {
  description = "Whether sample data was created"
  value       = var.create_sample_data
}

output "sample_data_files" {
  description = "Information about created sample data files"
  value = var.create_sample_data ? [
    for idx, file in var.sample_data_files : {
      blob_name      = file.blob_name
      container_name = file.container_name
      blob_url       = "https://${azurerm_storage_account.lifecycle_storage.name}.blob.core.windows.net/${file.container_name}/${file.blob_name}"
      size_bytes     = length(file.content)
    }
  ] : []
}

# Diagnostic Settings Information
output "storage_diagnostics_enabled" {
  description = "Whether storage diagnostics are enabled"
  value       = var.enable_storage_monitoring
}

output "storage_diagnostics_id" {
  description = "ID of the storage diagnostics setting"
  value       = var.enable_storage_monitoring ? azurerm_monitor_diagnostic_setting.storage_diagnostics[0].id : null
}

# Network Rules Information
output "storage_network_rules_id" {
  description = "ID of the storage account network rules"
  value       = azurerm_storage_account_network_rules.lifecycle_storage_rules.id
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    storage_account_name     = azurerm_storage_account.lifecycle_storage.name
    storage_account_tier     = azurerm_storage_account.lifecycle_storage.account_tier
    storage_replication_type = azurerm_storage_account.lifecycle_storage.account_replication_type
    containers_created       = length(azurerm_storage_container.containers)
    monitoring_enabled       = var.enable_storage_monitoring
    alerts_enabled          = var.enable_capacity_alerts || var.enable_transaction_alerts
    lifecycle_policy_enabled = var.lifecycle_policy_enabled
    sample_data_created     = var.create_sample_data
    environment             = var.environment
    location               = var.location
  }
}

# Cost Optimization Information
output "cost_optimization_features" {
  description = "Summary of cost optimization features enabled"
  value = {
    lifecycle_management = var.lifecycle_policy_enabled
    blob_versioning     = var.enable_blob_versioning
    soft_delete_enabled = var.enable_blob_soft_delete
    monitoring_enabled  = var.enable_storage_monitoring
    automated_tiering = {
      documents = {
        cool_tier_after_days    = var.document_lifecycle_rules.tier_to_cool_days
        archive_tier_after_days = var.document_lifecycle_rules.tier_to_archive_days
        delete_after_days       = var.document_lifecycle_rules.delete_after_days
      }
      logs = {
        cool_tier_after_days    = var.log_lifecycle_rules.tier_to_cool_days
        archive_tier_after_days = var.log_lifecycle_rules.tier_to_archive_days
        delete_after_days       = var.log_lifecycle_rules.delete_after_days
      }
    }
  }
}

# Monitoring Endpoints and Queries
output "monitoring_endpoints" {
  description = "Important monitoring endpoints and information"
  value = {
    log_analytics_workspace = {
      name         = azurerm_log_analytics_workspace.storage_monitoring.name
      workspace_id = azurerm_log_analytics_workspace.storage_monitoring.workspace_id
      portal_url   = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.storage_monitoring.id}"
    }
    storage_account_metrics = {
      name       = azurerm_storage_account.lifecycle_storage.name
      portal_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_account.lifecycle_storage.id}/metrics"
    }
    action_group = {
      name       = azurerm_monitor_action_group.storage_alerts.name
      portal_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_monitor_action_group.storage_alerts.id}"
    }
  }
}

# Security Information
output "security_features" {
  description = "Summary of security features enabled"
  value = {
    https_traffic_only         = azurerm_storage_account.lifecycle_storage.enable_https_traffic_only
    min_tls_version           = azurerm_storage_account.lifecycle_storage.min_tls_version
    managed_identity_enabled  = true
    network_rules_configured  = true
    diagnostic_logging_enabled = var.enable_storage_monitoring
    soft_delete_enabled       = var.enable_blob_soft_delete
    versioning_enabled        = var.enable_blob_versioning
  }
}

# Deployment Information
output "deployment_information" {
  description = "Information about the deployment"
  value = {
    terraform_version = ">=1.5.0"
    azurerm_provider_version = "~>3.80"
    deployment_time = timestamp()
    random_suffix = random_string.suffix.result
    resource_count = {
      storage_accounts = 1
      containers = length(azurerm_storage_container.containers)
      alerts = (var.enable_capacity_alerts ? 1 : 0) + (var.enable_transaction_alerts ? 1 : 0) + 1
      log_analytics_workspaces = 1
      logic_apps = var.enable_logic_app_alerts ? 1 : 0
      action_groups = 1
    }
  }
}