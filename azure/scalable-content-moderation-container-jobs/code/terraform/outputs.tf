# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Azure AI Content Safety Outputs
output "content_safety_name" {
  description = "Name of the Azure AI Content Safety resource"
  value       = azurerm_cognitive_account.content_safety.name
}

output "content_safety_endpoint" {
  description = "Endpoint URL for Azure AI Content Safety"
  value       = azurerm_cognitive_account.content_safety.endpoint
}

output "content_safety_id" {
  description = "Resource ID of the Azure AI Content Safety service"
  value       = azurerm_cognitive_account.content_safety.id
}

output "content_safety_primary_key" {
  description = "Primary access key for Azure AI Content Safety"
  value       = azurerm_cognitive_account.content_safety.primary_access_key
  sensitive   = true
}

# Service Bus Outputs
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_id" {
  description = "Resource ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "service_bus_connection_string" {
  description = "Primary connection string for Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "content_queue_name" {
  description = "Name of the content processing queue"
  value       = azurerm_servicebus_queue.content_queue.name
}

output "content_queue_id" {
  description = "Resource ID of the content processing queue"
  value       = azurerm_servicebus_queue.content_queue.id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "moderation_results_container_name" {
  description = "Name of the moderation results storage container"
  value       = azurerm_storage_container.moderation_results.name
}

output "audit_logs_container_name" {
  description = "Name of the audit logs storage container"
  value       = azurerm_storage_container.audit_logs.name
}

# Container Apps Outputs
output "container_apps_environment_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_apps_environment_id" {
  description = "Resource ID of the Container Apps environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_job_name" {
  description = "Name of the content processing container job"
  value       = azurerm_container_app_job.content_processor.name
}

output "container_job_id" {
  description = "Resource ID of the content processing container job"
  value       = azurerm_container_app_job.content_processor.id
}

output "container_job_identity_principal_id" {
  description = "Principal ID of the container job's managed identity"
  value       = azurerm_container_app_job.content_processor.identity[0].principal_id
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = var.enable_alerts ? azurerm_monitor_action_group.main[0].name : null
}

output "action_group_id" {
  description = "Resource ID of the monitoring action group"
  value       = var.enable_alerts ? azurerm_monitor_action_group.main[0].id : null
}

# Configuration Information
output "deployment_configuration" {
  description = "Key configuration details for the deployment"
  value = {
    environment                    = var.environment
    project_name                  = var.project_name
    location                      = var.location
    resource_suffix               = local.suffix
    content_safety_sku           = var.content_safety_sku
    service_bus_sku              = var.service_bus_sku
    storage_account_tier         = var.storage_account_tier
    storage_replication_type     = var.storage_replication_type
    container_job_cpu            = var.container_job_cpu
    container_job_memory         = var.container_job_memory
    container_job_parallelism    = var.container_job_parallelism
    scale_rule_message_count     = var.scale_rule_message_count
    log_analytics_enabled        = var.enable_log_analytics
    alerts_enabled               = var.enable_alerts
    managed_identity_enabled     = var.enable_managed_identity
    https_only_enabled           = var.enable_https_only
    storage_firewall_enabled     = var.enable_storage_firewall
  }
}

# Testing and Validation Commands
output "testing_commands" {
  description = "Commands to test the deployed infrastructure"
  value = {
    test_content_safety_api = "curl -X POST '${azurerm_cognitive_account.content_safety.endpoint}/contentsafety/text:analyze?api-version=2023-10-01' -H 'Ocp-Apim-Subscription-Key: <KEY>' -H 'Content-Type: application/json' -d '{\"text\": \"Test content\", \"categories\": [\"Hate\", \"SelfHarm\", \"Sexual\", \"Violence\"]}'"
    
    send_test_message = "az servicebus queue send --namespace-name '${azurerm_servicebus_namespace.main.name}' --resource-group '${azurerm_resource_group.main.name}' --queue-name '${azurerm_servicebus_queue.content_queue.name}' --body '{\"contentId\": \"test-001\", \"text\": \"Test content for moderation\", \"type\": \"text\"}'"
    
    check_queue_metrics = "az servicebus queue show --namespace-name '${azurerm_servicebus_namespace.main.name}' --resource-group '${azurerm_resource_group.main.name}' --name '${azurerm_servicebus_queue.content_queue.name}' --query 'messageCount'"
    
    check_job_executions = "az containerapp job execution list --name '${azurerm_container_app_job.content_processor.name}' --resource-group '${azurerm_resource_group.main.name}' --output table"
    
    view_job_logs = "az containerapp logs show --name '${azurerm_container_app_job.content_processor.name}' --resource-group '${azurerm_resource_group.main.name}' --follow"
    
    list_moderation_results = "az storage blob list --container-name '${azurerm_storage_container.moderation_results.name}' --account-name '${azurerm_storage_account.main.name}' --auth-mode login --output table"
    
    list_audit_logs = "az storage blob list --container-name '${azurerm_storage_container.audit_logs.name}' --account-name '${azurerm_storage_account.main.name}' --auth-mode login --output table"
  }
}

# Resource URLs for Azure Portal
output "azure_portal_urls" {
  description = "Direct URLs to resources in Azure Portal"
  value = {
    resource_group      = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    content_safety      = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.content_safety.id}/overview"
    service_bus         = "https://portal.azure.com/#@/resource${azurerm_servicebus_namespace.main.id}/overview"
    storage_account     = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/overview"
    container_apps_env  = "https://portal.azure.com/#@/resource${azurerm_container_app_environment.main.id}/overview"
    container_job       = "https://portal.azure.com/#@/resource${azurerm_container_app_job.content_processor.id}/overview"
    log_analytics       = var.enable_log_analytics ? "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main[0].id}/overview" : null
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    content_safety_s0     = "~$1 per 1,000 transactions"
    service_bus_standard  = "~$10 per million operations"
    storage_account_hot   = "~$0.02 per GB/month"
    container_apps_consumption = "~$0.000016 per second of execution"
    log_analytics_per_gb  = "~$2.76 per GB ingested"
    total_estimated_range = "$15-25 per day for moderate usage (1000 content items/hour)"
  }
}

# Security Information
output "security_configuration" {
  description = "Security features enabled in the deployment"
  value = {
    content_safety_managed_identity = azurerm_cognitive_account.content_safety.identity[0].type
    service_bus_managed_identity    = azurerm_servicebus_namespace.main.identity[0].type
    storage_managed_identity        = azurerm_storage_account.main.identity[0].type
    container_job_managed_identity  = azurerm_container_app_job.content_processor.identity[0].type
    https_only_storage             = azurerm_storage_account.main.https_traffic_only_enabled
    storage_firewall_enabled       = var.enable_storage_firewall
    tls_version                    = azurerm_storage_account.main.min_tls_version
    local_auth_disabled            = !azurerm_cognitive_account.content_safety.local_auth_enabled
  }
}