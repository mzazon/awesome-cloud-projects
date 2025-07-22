# Project and environment information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name used for resource naming"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for globally unique resource names"
  value       = random_id.suffix.hex
}

# Service account information
output "workspace_service_account_email" {
  description = "Email address of the Google Workspace automation service account"
  value       = google_service_account.workspace_automation.email
}

output "workspace_service_account_id" {
  description = "Unique ID of the Google Workspace automation service account"
  value       = google_service_account.workspace_automation.unique_id
}

# Secret Manager information
output "workspace_credentials_secret_name" {
  description = "Name of the Secret Manager secret containing Workspace credentials"
  value       = google_secret_manager_secret.workspace_credentials.secret_id
}

output "workspace_credentials_secret_id" {
  description = "Full resource ID of the Secret Manager secret"
  value       = google_secret_manager_secret.workspace_credentials.id
}

# Cloud Storage information
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for code artifacts"
  value       = google_storage_bucket.code_artifacts.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.code_artifacts.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.code_artifacts.self_link
}

# Pub/Sub information
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for code events"
  value       = google_pubsub_topic.code_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.code_events.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for code processing"
  value       = google_pubsub_subscription.code_processing.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.code_processing.id
}

# Cloud Run service information
output "code_review_service_name" {
  description = "Name of the code review Cloud Run service"
  value       = google_cloud_run_v2_service.code_review_service.name
}

output "code_review_service_url" {
  description = "URL of the code review Cloud Run service"
  value       = google_cloud_run_v2_service.code_review_service.uri
}

output "code_review_service_webhook_url" {
  description = "Webhook URL for the code review service (for repository configuration)"
  value       = "${google_cloud_run_v2_service.code_review_service.uri}/webhook"
}

output "docs_service_name" {
  description = "Name of the documentation update Cloud Run service"
  value       = google_cloud_run_v2_service.docs_service.name
}

output "docs_service_url" {
  description = "URL of the documentation update Cloud Run service"
  value       = google_cloud_run_v2_service.docs_service.uri
}

output "notification_service_name" {
  description = "Name of the notification Cloud Run service"
  value       = google_cloud_run_v2_service.notification_service.name
}

output "notification_service_url" {
  description = "URL of the notification Cloud Run service"
  value       = google_cloud_run_v2_service.notification_service.uri
}

# Cloud Scheduler information
output "scheduler_jobs" {
  description = "Information about created Cloud Scheduler jobs"
  value = var.enable_scheduler ? {
    weekly_doc_review = {
      name     = google_cloud_scheduler_job.weekly_doc_review[0].name
      schedule = google_cloud_scheduler_job.weekly_doc_review[0].schedule
    }
    monthly_cleanup = {
      name     = google_cloud_scheduler_job.monthly_cleanup[0].name
      schedule = google_cloud_scheduler_job.monthly_cleanup[0].schedule
    }
    weekly_summary = {
      name     = google_cloud_scheduler_job.weekly_summary[0].name
      schedule = google_cloud_scheduler_job.weekly_summary[0].schedule
    }
  } : {}
}

# Monitoring information
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard (if created)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.code_review_automation[0].id : null
}

output "alert_policy_id" {
  description = "ID of the monitoring alert policy (if created)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.code_review_service_errors[0].name : null
}

# Container registry information for building and deploying applications
output "container_images_to_build" {
  description = "List of container images that need to be built and pushed"
  value = {
    code_review_service = "${var.container_registry}/${var.project_id}/code-review-service:latest"
    docs_service       = "${var.container_registry}/${var.project_id}/docs-service:latest"
    notification_service = "${var.container_registry}/${var.project_id}/notification-service:latest"
  }
}

# API enablement status
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = var.enable_apis ? var.required_apis : []
}

# Webhook configuration for repository setup
output "webhook_configuration" {
  description = "Webhook configuration details for code repository setup"
  value = {
    webhook_url    = "${google_cloud_run_v2_service.code_review_service.uri}/webhook"
    content_type   = "application/json"
    events         = ["push", "pull_request"]
    secret         = "Configure webhook secret in your repository settings"
    ssl_verification = "enabled"
  }
}

# Google Workspace setup instructions
output "workspace_setup_instructions" {
  description = "Instructions for setting up Google Workspace domain-wide delegation"
  value = {
    service_account_email = google_service_account.workspace_automation.email
    service_account_id    = google_service_account.workspace_automation.unique_id
    oauth_scopes = [
      "https://www.googleapis.com/auth/documents",
      "https://www.googleapis.com/auth/drive",
      "https://www.googleapis.com/auth/gmail.send"
    ]
    domain_delegation_steps = [
      "1. Go to Google Admin Console (admin.google.com)",
      "2. Navigate to Security > API Controls > Domain-wide Delegation",
      "3. Add new API client with Client ID: ${google_service_account.workspace_automation.unique_id}",
      "4. Add OAuth scopes: https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/drive,https://www.googleapis.com/auth/gmail.send",
      "5. Save the configuration"
    ]
  }
}

# Resource naming information
output "resource_names" {
  description = "Generated names for all created resources"
  value = {
    service_account_name      = google_service_account.workspace_automation.account_id
    storage_bucket_name       = google_storage_bucket.code_artifacts.name
    pubsub_topic_name        = google_pubsub_topic.code_events.name
    pubsub_subscription_name = google_pubsub_subscription.code_processing.name
    code_review_service_name = google_cloud_run_v2_service.code_review_service.name
    docs_service_name        = google_cloud_run_v2_service.docs_service.name
    notification_service_name = google_cloud_run_v2_service.notification_service.name
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources (USD)"
  value = {
    message = "Costs depend on usage patterns. Key cost factors:"
    factors = [
      "Cloud Run: $0.40 per million requests + $0.0024 per GB/second",
      "Pub/Sub: $0.40 per million operations for messages < 1KB",
      "Cloud Storage: $0.020 per GB/month (Standard), $0.010 per GB/month (Nearline)",
      "Secret Manager: $0.06 per secret per month + $0.03 per 10,000 operations",
      "Cloud Scheduler: $0.10 per job per month",
      "Monitoring: Free tier includes dashboards and basic alerting"
    ]
    estimated_monthly_cost = "$15-30 for moderate usage (1000 webhook events, 100GB storage)"
  }
}

# Security and compliance information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    service_account_principle = "Least privilege access granted"
    secret_management        = "Credentials stored in Secret Manager with automatic encryption"
    network_security        = "Cloud Run services use HTTPS by default"
    data_encryption         = "All data encrypted at rest and in transit"
    audit_logging           = "Enabled through Google Cloud Audit Logs"
    iam_roles = [
      "secretmanager.secretAccessor",
      "storage.objectAdmin", 
      "pubsub.publisher",
      "monitoring.metricWriter"
    ]
  }
}

# Health check endpoints for monitoring
output "health_check_endpoints" {
  description = "Health check endpoints for monitoring service status"
  value = {
    code_review_service  = "${google_cloud_run_v2_service.code_review_service.uri}/health"
    docs_service        = "${google_cloud_run_v2_service.docs_service.uri}/health"
    notification_service = "${google_cloud_run_v2_service.notification_service.uri}/health"
  }
}

# Next steps for deployment
output "next_steps" {
  description = "Next steps to complete the deployment"
  value = [
    "1. Build and push container images to ${var.container_registry}/${var.project_id}/",
    "2. Configure Google Workspace domain-wide delegation using the provided service account details",
    "3. Set up repository webhooks using the provided webhook URL",
    "4. Test the webhook endpoint with a sample payload",
    "5. Configure notification recipients in your application code",
    "6. Review and customize Cloud Scheduler job schedules if needed",
    "7. Set up monitoring alert notification channels if desired"
  ]
}