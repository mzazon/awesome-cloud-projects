# Outputs for Azure Custom Vision and Logic Apps automation infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for training data and model artifacts"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "training_images_container_name" {
  description = "Name of the storage container for training images"
  value       = azurerm_storage_container.training_images.name
}

output "training_images_container_url" {
  description = "URL of the training images container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.training_images.name}"
}

output "model_artifacts_container_name" {
  description = "Name of the storage container for model artifacts"
  value       = azurerm_storage_container.model_artifacts.name
}

output "model_artifacts_container_url" {
  description = "URL of the model artifacts container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.model_artifacts.name}"
}

output "processed_images_container_name" {
  description = "Name of the storage container for processed images"
  value       = azurerm_storage_container.processed_images.name
}

output "processed_images_container_url" {
  description = "URL of the processed images container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.processed_images.name}"
}

# Custom Vision Service Information
output "custom_vision_training_name" {
  description = "Name of the Custom Vision training service"
  value       = azurerm_cognitive_account.custom_vision_training.name
}

output "custom_vision_training_endpoint" {
  description = "Endpoint URL for Custom Vision training service"
  value       = azurerm_cognitive_account.custom_vision_training.endpoint
}

output "custom_vision_training_key" {
  description = "Primary access key for Custom Vision training service"
  value       = azurerm_cognitive_account.custom_vision_training.primary_access_key
  sensitive   = true
}

output "custom_vision_training_id" {
  description = "Resource ID of the Custom Vision training service"
  value       = azurerm_cognitive_account.custom_vision_training.id
}

output "custom_vision_prediction_name" {
  description = "Name of the Custom Vision prediction service"
  value       = azurerm_cognitive_account.custom_vision_prediction.name
}

output "custom_vision_prediction_endpoint" {
  description = "Endpoint URL for Custom Vision prediction service"
  value       = azurerm_cognitive_account.custom_vision_prediction.endpoint
}

output "custom_vision_prediction_key" {
  description = "Primary access key for Custom Vision prediction service"
  value       = azurerm_cognitive_account.custom_vision_prediction.primary_access_key
  sensitive   = true
}

output "custom_vision_prediction_id" {
  description = "Resource ID of the Custom Vision prediction service"
  value       = azurerm_cognitive_account.custom_vision_prediction.id
}

output "custom_vision_project_id" {
  description = "ID of the created Custom Vision project"
  value       = jsondecode(azapi_resource.custom_vision_project.output).id
}

output "custom_vision_project_name" {
  description = "Name of the created Custom Vision project"
  value       = jsondecode(azapi_resource.custom_vision_project.output).name
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.retraining_workflow.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.retraining_workflow.id
}

output "logic_app_trigger_url" {
  description = "Callback URL for manually triggering the Logic App"
  value       = "https://management.azure.com${azurerm_logic_app_workflow.retraining_workflow.id}/triggers/When_a_blob_is_added_or_modified/run?api-version=2016-10-01"
}

output "logic_app_access_endpoint" {
  description = "Access endpoint for the Logic App"
  value       = azurerm_logic_app_workflow.retraining_workflow.access_endpoint
}

# API Connections
output "blob_storage_connection_id" {
  description = "Resource ID of the blob storage API connection"
  value       = azurerm_api_connection.blob_storage.id
}

output "blob_storage_connection_name" {
  description = "Name of the blob storage API connection"
  value       = azurerm_api_connection.blob_storage.name
}

output "http_connection_id" {
  description = "Resource ID of the HTTP API connection"
  value       = azurerm_api_connection.http.id
}

output "http_connection_name" {
  description = "Name of the HTTP API connection"
  value       = azurerm_api_connection.http.name
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Workspace ID for Log Analytics"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_resource_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "application_insights_name" {
  description = "Name of the Application Insights instance (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "Resource ID of the monitoring action group"
  value       = azurerm_monitor_action_group.main.id
}

output "training_success_alert_name" {
  description = "Name of the Custom Vision training success rate alert"
  value       = azurerm_monitor_metric_alert.training_success_rate.name
}

output "training_success_alert_id" {
  description = "Resource ID of the Custom Vision training success rate alert"
  value       = azurerm_monitor_metric_alert.training_success_rate.id
}

output "logic_app_failure_alert_name" {
  description = "Name of the Logic App failure alert"
  value       = azurerm_monitor_metric_alert.logic_app_failures.name
}

output "logic_app_failure_alert_id" {
  description = "Resource ID of the Logic App failure alert"
  value       = azurerm_monitor_metric_alert.logic_app_failures.id
}

output "storage_failure_alert_name" {
  description = "Name of the storage account failure alert"
  value       = azurerm_monitor_metric_alert.storage_failures.name
}

output "storage_failure_alert_id" {
  description = "Resource ID of the storage account failure alert"
  value       = azurerm_monitor_metric_alert.storage_failures.id
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group           = azurerm_resource_group.main.name
    storage_account         = azurerm_storage_account.main.name
    custom_vision_training  = azurerm_cognitive_account.custom_vision_training.name
    custom_vision_prediction = azurerm_cognitive_account.custom_vision_prediction.name
    custom_vision_project   = jsondecode(azapi_resource.custom_vision_project.output).name
    logic_app               = azurerm_logic_app_workflow.retraining_workflow.name
    log_analytics           = azurerm_log_analytics_workspace.main.name
    application_insights    = var.enable_application_insights ? azurerm_application_insights.main[0].name : "Not enabled"
    containers = {
      training_images   = azurerm_storage_container.training_images.name
      model_artifacts  = azurerm_storage_container.model_artifacts.name
      processed_images = azurerm_storage_container.processed_images.name
    }
    alerts = {
      training_success  = azurerm_monitor_metric_alert.training_success_rate.name
      logic_app_failure = azurerm_monitor_metric_alert.logic_app_failures.name
      storage_failure   = azurerm_monitor_metric_alert.storage_failures.name
    }
    api_connections = {
      blob_storage = azurerm_api_connection.blob_storage.name
      http         = azurerm_api_connection.http.name
    }
  }
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = {
    upload_training_data = "Upload training images to the '${azurerm_storage_container.training_images.name}' container to trigger automated retraining"
    monitor_training = "Check the Logic App run history and Log Analytics workspace for training progress and results"
    view_models = "Access trained models through the Custom Vision portal or API using the provided endpoints and keys"
    storage_endpoint = azurerm_storage_account.main.primary_blob_endpoint
    custom_vision_portal = "https://www.customvision.ai/"
    minimum_training_images = "Ensure at least 15 images are present in the training container before triggering retraining"
    lifecycle_policy = "Processed images will be automatically moved to Cool tier after 30 days, Archive after 90 days, and deleted after 365 days"
  }
}

# Connection Strings (for application configuration)
output "connection_strings" {
  description = "Connection strings for application configuration"
  value = {
    storage_account = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.main.name};AccountKey=${azurerm_storage_account.main.primary_access_key};EndpointSuffix=core.windows.net"
    log_analytics = "workspace-id=${azurerm_log_analytics_workspace.main.workspace_id};shared-key=${azurerm_log_analytics_workspace.main.primary_shared_key}"
    application_insights = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : "Not enabled"
  }
  sensitive = true
}

# Resource URLs for easy access
output "resource_urls" {
  description = "Direct URLs to access deployed resources"
  value = {
    logic_app_designer = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.retraining_workflow.id}/designer"
    logic_app_overview = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.retraining_workflow.id}/overview"
    storage_account = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/overview"
    custom_vision_training = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.custom_vision_training.id}/overview"
    custom_vision_prediction = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.custom_vision_prediction.id}/overview"
    log_analytics = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
    application_insights = var.enable_application_insights ? "https://portal.azure.com/#@/resource${azurerm_application_insights.main[0].id}/overview" : null
    resource_group = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
  }
}

# Environment-specific outputs
output "environment_info" {
  description = "Environment-specific information and configuration"
  value = {
    environment = var.environment
    location = var.location
    project_name = var.project_name
    random_suffix = random_string.suffix.result
    deployment_timestamp = timestamp()
    terraform_version = "~> 1.0"
    azurerm_provider_version = "~> 3.80"
    subscription_id = data.azurerm_client_config.current.subscription_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }
}

# Security and compliance information
output "security_configuration" {
  description = "Security and compliance configuration details"
  value = {
    storage_https_only = true
    storage_min_tls_version = "TLS1_2"
    storage_public_access_enabled = var.enable_public_access
    storage_versioning_enabled = var.enable_blob_versioning
    storage_soft_delete_enabled = var.enable_soft_delete
    cognitive_services_public_access = true
    diagnostic_logs_enabled = true
    monitoring_alerts_configured = true
    lifecycle_management_enabled = true
  }
}

# Cost optimization information
output "cost_optimization" {
  description = "Cost optimization features and recommendations"
  value = {
    storage_access_tier = var.storage_account_access_tier
    storage_replication_type = var.storage_account_replication_type
    lifecycle_policy_enabled = true
    cool_tier_transition_days = 30
    archive_tier_transition_days = 90
    deletion_after_days = 365
    custom_vision_sku = var.custom_vision_sku
    log_analytics_sku = var.log_analytics_sku
    log_retention_days = var.log_analytics_retention_in_days
    recommendations = [
      "Monitor storage costs and adjust access tiers as needed",
      "Review Custom Vision usage and consider F0 tier for development",
      "Implement data retention policies based on business requirements",
      "Use Application Insights for detailed performance monitoring"
    ]
  }
}