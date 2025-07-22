# Output values for Azure Video Content Moderation Solution
# These outputs provide essential information for solution integration and validation

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all video moderation resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where the resource group is located"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure AI Vision Service Outputs
output "ai_vision_name" {
  description = "Name of the Azure AI Vision service"
  value       = azurerm_cognitive_account.ai_vision.name
}

output "ai_vision_endpoint" {
  description = "Endpoint URL for the Azure AI Vision service"
  value       = azurerm_cognitive_account.ai_vision.endpoint
}

output "ai_vision_primary_key" {
  description = "Primary access key for Azure AI Vision service"
  value       = azurerm_cognitive_account.ai_vision.primary_access_key
  sensitive   = true
}

output "ai_vision_secondary_key" {
  description = "Secondary access key for Azure AI Vision service"
  value       = azurerm_cognitive_account.ai_vision.secondary_access_key
  sensitive   = true
}

output "ai_vision_id" {
  description = "Resource ID of the Azure AI Vision service"
  value       = azurerm_cognitive_account.ai_vision.id
}

# Event Hubs Namespace Outputs
output "eventhub_namespace_name" {
  description = "Name of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_namespace_hostname" {
  description = "Hostname of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "eventhub_namespace_id" {
  description = "Resource ID of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.main.id
}

# Event Hub Outputs
output "eventhub_name" {
  description = "Name of the video frames Event Hub"
  value       = azurerm_eventhub.video_frames.name
}

output "eventhub_partition_count" {
  description = "Number of partitions in the Event Hub"
  value       = azurerm_eventhub.video_frames.partition_count
}

output "eventhub_connection_string" {
  description = "Connection string for accessing the Event Hub"
  value       = azurerm_eventhub_authorization_rule.main.primary_connection_string
  sensitive   = true
}

output "eventhub_primary_key" {
  description = "Primary access key for Event Hub"
  value       = azurerm_eventhub_authorization_rule.main.primary_key
  sensitive   = true
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for moderation results"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_blob_endpoint" {
  description = "Blob service endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "moderation_results_container_name" {
  description = "Name of the storage container for moderation results"
  value       = azurerm_storage_container.moderation_results.name
}

# Stream Analytics Job Outputs
output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.name
}

output "stream_analytics_job_id" {
  description = "Resource ID of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.id
}

output "stream_analytics_streaming_units" {
  description = "Number of streaming units configured for the job"
  value       = azurerm_stream_analytics_job.main.streaming_units
}

# Logic App Outputs
output "logic_app_name" {
  description = "Name of the Logic App for response workflows"
  value       = azurerm_logic_app_workflow.main.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App"
  value       = azurerm_logic_app_workflow.main.id
}

output "logic_app_access_endpoint" {
  description = "Access endpoint for the Logic App"
  value       = azurerm_logic_app_workflow.main.access_endpoint
  sensitive   = true
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "application_insights_name" {
  description = "Name of Application Insights instance (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Configuration Information
output "content_moderation_thresholds" {
  description = "Configured content moderation thresholds"
  value       = var.content_moderation_thresholds
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# Connection Information for Applications
output "video_moderation_config" {
  description = "Configuration object for video moderation applications"
  value = {
    ai_vision = {
      endpoint = azurerm_cognitive_account.ai_vision.endpoint
      name     = azurerm_cognitive_account.ai_vision.name
    }
    event_hub = {
      namespace_name = azurerm_eventhub_namespace.main.name
      hub_name       = azurerm_eventhub.video_frames.name
      partition_count = azurerm_eventhub.video_frames.partition_count
    }
    storage = {
      account_name    = azurerm_storage_account.main.name
      container_name  = azurerm_storage_container.moderation_results.name
      blob_endpoint   = azurerm_storage_account.main.primary_blob_endpoint
    }
    stream_analytics = {
      job_name = azurerm_stream_analytics_job.main.name
      streaming_units = azurerm_stream_analytics_job.main.streaming_units
    }
    logic_app = {
      name = azurerm_logic_app_workflow.main.name
    }
    thresholds = var.content_moderation_thresholds
  }
  sensitive = false
}

# Validation Information
output "deployment_validation" {
  description = "Information for validating the deployment"
  value = {
    resource_count = {
      resource_group    = 1
      ai_vision        = 1
      event_hub_namespace = 1
      event_hub        = 1
      storage_account  = 1
      storage_containers = 2
      stream_analytics = 1
      logic_app        = 1
      monitoring       = var.enable_monitoring ? 2 : 0
    }
    configuration = {
      location           = var.location
      environment        = var.environment
      monitoring_enabled = var.enable_monitoring
      auto_inflate       = var.enable_auto_inflate
    }
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Azure CLI commands to validate and test the deployment"
  value = {
    test_ai_vision = "az cognitiveservices account show --name ${azurerm_cognitive_account.ai_vision.name} --resource-group ${azurerm_resource_group.main.name}"
    test_event_hub = "az eventhubs eventhub show --namespace-name ${azurerm_eventhub_namespace.main.name} --name ${azurerm_eventhub.video_frames.name} --resource-group ${azurerm_resource_group.main.name}"
    start_stream_analytics = "az stream-analytics job start --name ${azurerm_stream_analytics_job.main.name} --resource-group ${azurerm_resource_group.main.name}"
    list_storage_containers = "az storage container list --account-name ${azurerm_storage_account.main.name}"
  }
}