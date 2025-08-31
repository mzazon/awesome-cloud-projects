# Outputs for GCP Email Automation with Vertex AI Agent Builder and MCP
# This file defines all output values from the Terraform configuration

# Project and Regional Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name used for resource tagging"
  value       = var.environment
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the service account created for email automation"
  value       = google_service_account.email_automation.email
}

output "service_account_id" {
  description = "The service account ID for email automation"
  value       = google_service_account.email_automation.account_id
}

output "service_account_unique_id" {
  description = "The unique ID of the service account"
  value       = google_service_account.email_automation.unique_id
}

# Cloud Functions Information
output "gmail_webhook_function_name" {
  description = "Name of the Gmail webhook Cloud Function"
  value       = google_cloud_functions2_function.gmail_webhook.name
}

output "gmail_webhook_function_url" {
  description = "HTTPS trigger URL for the Gmail webhook function"
  value       = google_cloud_functions2_function.gmail_webhook.service_config[0].uri
}

output "mcp_integration_function_name" {
  description = "Name of the MCP integration Cloud Function"
  value       = google_cloud_functions2_function.mcp_integration.name
}

output "mcp_integration_function_url" {
  description = "HTTPS trigger URL for the MCP integration function"
  value       = google_cloud_functions2_function.mcp_integration.service_config[0].uri
}

output "response_generator_function_name" {
  description = "Name of the response generator Cloud Function"
  value       = google_cloud_functions2_function.response_generator.name
}

output "response_generator_function_url" {
  description = "HTTPS trigger URL for the response generator function"
  value       = google_cloud_functions2_function.response_generator.service_config[0].uri
}

output "email_workflow_function_name" {
  description = "Name of the email workflow orchestration Cloud Function"
  value       = google_cloud_functions2_function.email_workflow.name
}

output "email_workflow_function_url" {
  description = "HTTPS trigger URL for the email workflow function"
  value       = google_cloud_functions2_function.email_workflow.service_config[0].uri
}

# Pub/Sub Information
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for Gmail notifications"
  value       = google_pubsub_topic.gmail_notifications.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.gmail_notifications.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for Gmail webhook"
  value       = google_pubsub_subscription.gmail_webhook.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.gmail_webhook.id
}

output "pubsub_push_endpoint" {
  description = "Push endpoint URL configured for the Pub/Sub subscription"
  value       = google_pubsub_subscription.gmail_webhook.push_config[0].push_endpoint
}

# Storage Information
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

output "function_source_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.self_link
}

# Secret Manager Information
output "mcp_config_secret_name" {
  description = "Name of the Secret Manager secret containing MCP configuration"
  value       = google_secret_manager_secret.mcp_config.secret_id
}

output "mcp_config_secret_id" {
  description = "Full resource ID of the MCP configuration secret"
  value       = google_secret_manager_secret.mcp_config.id
}

# Logging Information
output "logging_sink_name" {
  description = "Name of the Cloud Logging sink for email automation monitoring"
  value       = google_logging_project_sink.email_automation_sink.name
}

output "logging_sink_destination" {
  description = "Destination of the Cloud Logging sink"
  value       = google_logging_project_sink.email_automation_sink.destination
}

output "logging_sink_writer_identity" {
  description = "Writer identity for the Cloud Logging sink"
  value       = google_logging_project_sink.email_automation_sink.writer_identity
}

# Resource Naming Information
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Gmail Integration Setup Information
output "gmail_setup_instructions" {
  description = "Instructions for setting up Gmail push notifications"
  value = <<-EOT
    To complete the Gmail integration setup:
    
    1. Enable Gmail API push notifications:
       - Go to the Gmail API console
       - Configure push notifications to use this Pub/Sub topic:
         projects/${var.project_id}/topics/${google_pubsub_topic.gmail_notifications.name}
    
    2. Webhook endpoint for testing:
       ${google_cloud_functions2_function.gmail_webhook.service_config[0].uri}
    
    3. MCP integration endpoint:
       ${google_cloud_functions2_function.mcp_integration.service_config[0].uri}
    
    4. Email workflow endpoint:
       ${google_cloud_functions2_function.email_workflow.service_config[0].uri}
  EOT
}

# Monitoring and Observability
output "function_logs_filter" {
  description = "Cloud Logging filter for viewing all email automation function logs"
  value = <<-EOT
    resource.type="cloud_function"
    AND (
      resource.labels.function_name="${google_cloud_functions2_function.gmail_webhook.name}"
      OR resource.labels.function_name="${google_cloud_functions2_function.mcp_integration.name}"
      OR resource.labels.function_name="${google_cloud_functions2_function.response_generator.name}"
      OR resource.labels.function_name="${google_cloud_functions2_function.email_workflow.name}"
    )
  EOT
}

# API Endpoints for Testing
output "test_endpoints" {
  description = "API endpoints for testing the email automation system"
  value = {
    gmail_webhook     = google_cloud_functions2_function.gmail_webhook.service_config[0].uri
    mcp_integration   = google_cloud_functions2_function.mcp_integration.service_config[0].uri
    response_generator = google_cloud_functions2_function.response_generator.service_config[0].uri
    email_workflow    = google_cloud_functions2_function.email_workflow.service_config[0].uri
  }
}

# Resource Labels Applied
output "applied_labels" {
  description = "Labels applied to resources during deployment"
  value = merge(
    {
      environment = var.environment
      service     = "email-automation"
    },
    var.labels
  )
}

# Enabled APIs
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value       = local.required_apis
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Notes about cost optimization for the deployed resources"
  value = <<-EOT
    Cost Optimization Notes:
    
    1. Cloud Functions are configured with appropriate memory and timeout limits
    2. Storage bucket has lifecycle rules to delete old objects after ${var.storage_lifecycle_age_days} days
    3. Minimum function instances set to ${var.min_function_instances} to balance cost and performance
    4. Pub/Sub subscription configured with retry policies to prevent message loss
    
    Monitor usage in Cloud Console and adjust function configurations based on actual load patterns.
  EOT
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary for the deployed resources"
  value = {
    service_account_principle = "roles/least-privilege applied with minimal required permissions"
    function_access          = var.enable_public_function_access ? "Public access enabled for webhooks" : "Authenticated access only"
    secret_management        = "MCP configuration stored in Secret Manager with automatic replication"
    logging_enabled          = "Comprehensive logging enabled for all functions"
    iam_bindings            = "Service account granted minimal required roles for operation"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps to complete the email automation setup"
  value = <<-EOT
    Next Steps:
    
    1. Configure Gmail API push notifications to use the Pub/Sub topic
    2. Test the webhook endpoint with sample email data
    3. Configure enterprise data sources for MCP integration
    4. Set up monitoring dashboards in Cloud Console
    5. Configure alerting policies for function errors
    6. Review and adjust function memory/timeout based on actual usage
    7. Implement additional security measures as needed for production use
    
    For detailed testing instructions, refer to the recipe documentation.
  EOT
}