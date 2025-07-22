# Outputs for Code Review Automation Infrastructure
# This file defines the output values that will be displayed after deployment

# Project and Resource Identification
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "deployment_region" {
  description = "The Google Cloud region where regional resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for resource tracking"
  value       = random_id.suffix.hex
}

# Cloud Source Repository Information
output "repository_name" {
  description = "Name of the created Cloud Source Repository"
  value       = google_sourcerepo_repository.code_review_repo.name
}

output "repository_url" {
  description = "Clone URL for the Cloud Source Repository"
  value       = google_sourcerepo_repository.code_review_repo.url
}

output "repository_clone_command" {
  description = "Command to clone the repository locally"
  value       = "gcloud source repos clone ${google_sourcerepo_repository.code_review_repo.name} --project=${var.project_id}"
}

# Cloud Function Information
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.code_review_trigger.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.code_review_trigger.service_config[0].uri
}

output "function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Storage Resources
output "function_source_bucket" {
  description = "Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

output "analysis_results_bucket" {
  description = "Cloud Storage bucket for analysis results and logs"
  value       = google_storage_bucket.analysis_results.name
}

output "analysis_results_url" {
  description = "Cloud Console URL to view analysis results"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.analysis_results.name}"
}

# AI and Configuration
output "vertex_ai_model" {
  description = "Vertex AI model being used for code analysis"
  value       = var.vertex_ai_model
}

output "vertex_ai_config_secret" {
  description = "Secret Manager secret containing Vertex AI configuration"
  value       = google_secret_manager_secret.vertex_ai_config.secret_id
}

output "supported_languages" {
  description = "List of programming languages supported for analysis"
  value       = var.supported_languages
}

# Firebase Studio Information (conditional)
output "firebase_project_enabled" {
  description = "Whether Firebase Studio integration is enabled"
  value       = var.enable_firebase_studio
}

output "firebase_studio_workspace_site" {
  description = "Firebase Hosting site ID for Studio workspace (if enabled)"
  value       = var.enable_firebase_studio ? google_firebase_hosting_site.studio_workspace[0].site_id : "Not enabled"
}

output "firebase_studio_url" {
  description = "URL to access Firebase Studio workspace (if enabled)"
  value       = var.enable_firebase_studio ? "https://studio.firebase.google.com/project/${var.project_id}" : "Firebase Studio not enabled"
}

# Eventarc and Triggers
output "eventarc_trigger_name" {
  description = "Name of the Eventarc trigger for repository events"
  value       = google_eventarc_trigger.repo_events.name
}

output "eventarc_trigger_events" {
  description = "Events that trigger the code review automation"
  value       = [for criteria in google_eventarc_trigger.repo_events.matching_criteria : criteria.value]
}

# Monitoring and Logging (conditional)
output "monitoring_enabled" {
  description = "Whether Cloud Monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "notification_channels" {
  description = "Email addresses configured for monitoring alerts"
  value       = var.notification_channels
  sensitive   = true
}

output "alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_error_rate[0].display_name : "Monitoring not enabled"
}

output "logging_sink_name" {
  description = "Name of the Cloud Logging sink for analysis logs"
  value       = google_logging_project_sink.analysis_logs.name
}

# Security and Access
output "required_apis_enabled" {
  description = "List of Google Cloud APIs that were enabled"
  value       = local.required_apis
}

output "service_account_roles" {
  description = "IAM roles assigned to the Cloud Function service account"
  value = [
    "roles/aiplatform.user",
    "roles/source.reader",
    "roles/storage.objectAdmin",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/secretmanager.secretAccessor",
    "roles/eventarc.eventReceiver"
  ]
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed code review automation system"
  value = {
    repository_name       = google_sourcerepo_repository.code_review_repo.name
    function_name        = google_cloudfunctions2_function.code_review_trigger.name
    ai_model            = var.vertex_ai_model
    supported_languages = var.supported_languages
    monitoring_enabled  = var.enable_monitoring
    firebase_enabled    = var.enable_firebase_studio
    security_scanning   = var.enable_security_scanning
    max_concurrent      = var.max_concurrent_reviews
    deployment_region   = var.region
    deployment_id       = random_id.suffix.hex
  }
}

# Testing and Validation
output "webhook_test_command" {
  description = "Curl command to test the webhook endpoint"
  value = <<-EOT
    curl -X POST "${google_cloudfunctions2_function.code_review_trigger.service_config[0].uri}" \
      -H "Content-Type: application/json" \
      -d '{
        "eventType": "push",
        "repository": "${google_sourcerepo_repository.code_review_repo.name}",
        "changedFiles": [{
          "path": "test.js",
          "content": "function test() { eval(userInput); }"
        }]
      }'
  EOT
}

output "repository_webhook_setup_instructions" {
  description = "Instructions for setting up repository webhooks"
  value = <<-EOT
    To complete the setup:
    1. Go to Cloud Console > Source Repositories
    2. Select repository: ${google_sourcerepo_repository.code_review_repo.name}
    3. Configure Cloud Build trigger pointing to: ${google_cloudfunctions2_function.code_review_trigger.service_config[0].uri}
    4. Set trigger events: push, pull_request
    5. Test with: git push origin main
  EOT
}

# Cost and Resource Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost range for resources (USD)"
  value = "Estimated $15-50/month depending on usage (Cloud Functions: $0.40/million invocations, Vertex AI: $0.25/1K characters, Storage: $0.02/GB)"
}

output "resource_cleanup_command" {
  description = "Terraform command to cleanup all resources"
  value = "terraform destroy -auto-approve"
}

# Integration Information
output "cloud_console_links" {
  description = "Direct links to manage resources in Cloud Console"
  value = {
    source_repositories = "https://console.cloud.google.com/source/repos?project=${var.project_id}"
    cloud_functions     = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    vertex_ai          = "https://console.cloud.google.com/ai/platform?project=${var.project_id}"
    cloud_storage      = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    monitoring         = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    logs               = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    firebase_studio    = var.enable_firebase_studio ? "https://studio.firebase.google.com/project/${var.project_id}" : "Not enabled"
  }
}