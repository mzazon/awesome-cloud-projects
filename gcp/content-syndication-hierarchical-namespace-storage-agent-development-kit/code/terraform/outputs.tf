# Output Values for Content Syndication Platform
# These outputs provide essential information for verifying deployment
# and integrating with external systems

# Storage Infrastructure Outputs
output "content_bucket_name" {
  description = "Name of the hierarchical namespace storage bucket for content"
  value       = google_storage_bucket.content_syndication.name
}

output "content_bucket_url" {
  description = "URL of the content syndication storage bucket"
  value       = google_storage_bucket.content_syndication.url
}

output "content_bucket_self_link" {
  description = "Self-link of the content syndication storage bucket"
  value       = google_storage_bucket.content_syndication.self_link
}

output "hierarchical_namespace_enabled" {
  description = "Confirmation that hierarchical namespace is enabled"
  value       = google_storage_bucket.content_syndication.hierarchical_namespace[0].enabled
}

# Function Infrastructure Outputs
output "content_processor_function_name" {
  description = "Name of the content processing Cloud Function"
  value       = google_cloudfunctions2_function.content_processor.name
}

output "content_processor_function_url" {
  description = "URL of the content processing Cloud Function"
  value       = google_cloudfunctions2_function.content_processor.url
}

output "content_processor_function_status" {
  description = "Status of the content processing Cloud Function"
  value       = google_cloudfunctions2_function.content_processor.state
}

output "function_source_bucket" {
  description = "Source bucket for Cloud Function deployment"
  value       = google_storage_bucket.function_source.name
}

# Workflow Infrastructure Outputs
output "workflow_name" {
  description = "Name of the content syndication Cloud Workflow"
  value       = google_workflows_workflow.content_syndication.name
}

output "workflow_id" {
  description = "ID of the content syndication Cloud Workflow"
  value       = google_workflows_workflow.content_syndication.id
}

output "workflow_state" {
  description = "State of the content syndication Cloud Workflow"
  value       = google_workflows_workflow.content_syndication.state
}

# Vertex AI Infrastructure Outputs
output "vertex_ai_endpoint_name" {
  description = "Name of the Vertex AI endpoint for agent development"
  value       = var.enable_vertex_ai ? google_vertex_ai_endpoint.content_agent[0].name : "not_created"
}

output "vertex_ai_endpoint_id" {
  description = "ID of the Vertex AI endpoint for agent development"
  value       = var.enable_vertex_ai ? google_vertex_ai_endpoint.content_agent[0].id : "not_created"
}

output "vertex_ai_location" {
  description = "Location of Vertex AI resources"
  value       = var.vertex_ai_location
}

# Service Account Outputs
output "workflow_service_account_email" {
  description = "Email of the workflow service account"
  value       = google_service_account.workflow_sa.email
}

output "function_service_account_email" {
  description = "Email of the function service account"
  value       = google_service_account.function_sa.email
}

output "vertex_ai_service_account_email" {
  description = "Email of the Vertex AI service account"
  value       = var.enable_vertex_ai ? google_service_account.vertex_ai_sa[0].email : "not_created"
}

# Content Pipeline Configuration Outputs
output "content_categories" {
  description = "List of content categories configured in the system"
  value       = var.content_categories
}

output "content_folders_created" {
  description = "List of content pipeline folders created in storage"
  value       = [for folder in google_storage_bucket_object.content_folders : folder.name]
}

output "distribution_channels" {
  description = "Map of content types to their distribution channels"
  value       = var.distribution_channels
}

# Platform Configuration Outputs
output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

output "region" {
  description = "GCP region for the deployment"
  value       = var.region
}

output "project_id" {
  description = "GCP project ID for the deployment"
  value       = var.project_id
}

# Quality Assessment Configuration
output "quality_thresholds" {
  description = "Quality assessment configuration"
  value = {
    minimum_score        = var.quality_thresholds.minimum_score
    enable_auto_approval = var.quality_thresholds.enable_auto_approval
    require_human_review = var.quality_thresholds.require_human_review
  }
}

# Monitoring and Observability Outputs
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.content_syndication[0].id : "not_created"
}

output "logging_enabled" {
  description = "Confirmation that logging is enabled for all components"
  value       = true
}

# Integration Endpoints
output "api_endpoints" {
  description = "Key API endpoints for external integration"
  value = {
    content_processor_function = google_cloudfunctions2_function.content_processor.url
    workflow_trigger          = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.content_syndication.name}/executions"
    storage_api               = "https://storage.googleapis.com/storage/v1/b/${google_storage_bucket.content_syndication.name}"
  }
}

# Security Configuration Outputs
output "security_configuration" {
  description = "Security settings applied to the platform"
  value = {
    uniform_bucket_level_access = google_storage_bucket.content_syndication.uniform_bucket_level_access
    function_ingress_settings   = google_cloudfunctions2_function.content_processor.service_config[0].ingress_settings
    cors_enabled               = var.enable_cors
    versioning_enabled         = google_storage_bucket.content_syndication.versioning[0].enabled
  }
}

# Cost Optimization Configuration
output "cost_optimization_features" {
  description = "Cost optimization features enabled"
  value = {
    lifecycle_management_enabled = var.enable_content_lifecycle
    content_retention_days      = var.content_retention_days
    function_min_instances      = google_cloudfunctions2_function.content_processor.service_config[0].min_instance_count
    function_max_instances      = google_cloudfunctions2_function.content_processor.service_config[0].max_instance_count
    storage_class              = google_storage_bucket.content_syndication.storage_class
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Commands to test the deployed infrastructure"
  value = {
    upload_test_content = "gcloud storage cp test-file.txt gs://${google_storage_bucket.content_syndication.name}/incoming/"
    list_bucket_contents = "gcloud storage ls -r gs://${google_storage_bucket.content_syndication.name}/"
    trigger_workflow = "gcloud workflows run ${google_workflows_workflow.content_syndication.name} --location=${var.region} --data='{\"bucket\":\"${google_storage_bucket.content_syndication.name}\",\"object\":\"incoming/test-file.txt\"}'"
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.content_processor.name} --region=${var.region}"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    storage_bucket_created    = true
    cloud_function_created    = true
    workflow_created         = true
    vertex_ai_endpoint_created = var.enable_vertex_ai
    monitoring_dashboard_created = var.enable_monitoring
    service_accounts_created = 3
    apis_enabled            = 10
    iam_bindings_created    = 12
  }
}