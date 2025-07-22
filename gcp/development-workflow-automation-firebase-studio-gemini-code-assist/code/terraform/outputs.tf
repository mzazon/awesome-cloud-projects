# Project and configuration outputs
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region used for resources"
  value       = var.region
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

# Resource naming outputs
output "resource_name_prefix" {
  description = "Common prefix used for resource naming"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = random_id.suffix.hex
}

# Storage outputs
output "dev_artifacts_bucket_name" {
  description = "Name of the Cloud Storage bucket for development artifacts"
  value       = google_storage_bucket.dev_artifacts.name
}

output "dev_artifacts_bucket_url" {
  description = "URL of the development artifacts bucket"
  value       = google_storage_bucket.dev_artifacts.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# Pub/Sub outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for development events"
  value       = google_pubsub_topic.dev_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.dev_events.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.dev_events_sub.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic"
  value       = google_pubsub_topic.dead_letter.name
}

# Cloud Functions outputs
output "code_review_function_name" {
  description = "Name of the code review automation function"
  value       = google_cloudfunctions2_function.code_review.name
}

output "code_review_function_url" {
  description = "URL of the code review function"
  value       = google_cloudfunctions2_function.code_review.service_config[0].uri
}

output "code_review_function_status" {
  description = "Status of the code review function"
  value       = google_cloudfunctions2_function.code_review.state
}

# Service Account outputs
output "workflow_service_account_email" {
  description = "Email address of the workflow service account"
  value       = google_service_account.workflow_sa.email
}

output "workflow_service_account_id" {
  description = "Unique ID of the workflow service account"
  value       = google_service_account.workflow_sa.unique_id
}

# Firebase outputs
output "firebase_project_id" {
  description = "Firebase project ID"
  value       = google_firebase_project.default.project
}

output "firebase_hosting_site_id" {
  description = "Firebase Hosting site ID (if enabled)"
  value       = var.enable_firebase_hosting ? google_firebase_hosting_site.dev_workspace[0].site_id : null
}

output "firebase_hosting_default_url" {
  description = "Default URL for Firebase Hosting site (if enabled)"
  value       = var.enable_firebase_hosting ? "https://${google_firebase_hosting_site.dev_workspace[0].site_id}.web.app" : null
}

output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.workspace_db.name
}

# Vertex AI outputs
output "workbench_instance_name" {
  description = "Name of the Vertex AI Workbench instance (if enabled)"
  value       = var.enable_vertex_ai ? google_workbench_instance.dev_workbench[0].name : null
}

output "workbench_instance_url" {
  description = "URL to access the Vertex AI Workbench instance (if enabled)"
  value       = var.enable_vertex_ai ? "https://console.cloud.google.com/vertex-ai/workbench/instances?project=${var.project_id}" : null
}

# Monitoring outputs
output "monitoring_dashboard_url" {
  description = "URL to the Cloud Monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.workflow_dashboard[0].id}?project=${var.project_id}" : null
}

output "alert_policy_name" {
  description = "Name of the monitoring alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_errors[0].name : null
}

output "notification_channel_id" {
  description = "ID of the notification channel (if email provided)"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email[0].id : null
}

# Cloud Build outputs
output "build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.deploy_trigger.name
}

output "build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.deploy_trigger.trigger_id
}

# Secret Manager outputs
output "ai_config_secret_name" {
  description = "Name of the AI configuration secret"
  value       = google_secret_manager_secret.ai_config.secret_id
}

output "ai_config_secret_id" {
  description = "Full resource ID of the AI configuration secret"
  value       = google_secret_manager_secret.ai_config.id
}

# Integration and testing outputs
output "gcloud_commands" {
  description = "Useful gcloud commands for testing and management"
  value = {
    test_function = "gcloud functions call ${google_cloudfunctions2_function.code_review.name} --region=${var.region}"
    view_logs     = "gcloud functions logs read ${google_cloudfunctions2_function.code_review.name} --region=${var.region} --limit=50"
    list_buckets  = "gsutil ls -p ${var.project_id}"
    test_upload   = "echo 'test content' | gsutil cp - gs://${google_storage_bucket.dev_artifacts.name}/test-file.txt"
    pubsub_pull   = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.dev_events_sub.name} --auto-ack --limit=10"
  }
}

# Development workflow setup commands
output "setup_commands" {
  description = "Commands to set up the development workflow"
  value = {
    set_project   = "gcloud config set project ${var.project_id}"
    auth_firebase = "firebase login && firebase use ${var.project_id}"
    test_workflow = "echo '{\"prompt\": \"Create a React component\", \"type\": \"component\"}' | gsutil cp - gs://${google_storage_bucket.dev_artifacts.name}/requests/test-request.json"
  }
}

# URLs for accessing services
output "service_urls" {
  description = "URLs for accessing various services"
  value = {
    cloud_console    = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
    storage_browser  = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    functions_console = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    firebase_console = "https://console.firebase.google.com/project/${var.project_id}"
    vertex_ai_console = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
    monitoring_console = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

# Configuration summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    project_id                = var.project_id
    region                   = var.region
    environment              = var.environment
    storage_bucket           = google_storage_bucket.dev_artifacts.name
    function_name            = google_cloudfunctions2_function.code_review.name
    pubsub_topic            = google_pubsub_topic.dev_events.name
    firebase_hosting_enabled = var.enable_firebase_hosting
    vertex_ai_enabled       = var.enable_vertex_ai
    monitoring_enabled      = var.enable_monitoring
    gemini_model           = var.gemini_model
  }
}

# Next steps for users
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Set up your local environment: gcloud config set project ${var.project_id}",
    "2. Authenticate with Firebase: firebase login && firebase use ${var.project_id}",
    "3. Test the workflow by uploading a sample file: gsutil cp test-file.txt gs://${google_storage_bucket.dev_artifacts.name}/",
    "4. Monitor function execution: gcloud functions logs read ${google_cloudfunctions2_function.code_review.name} --region=${var.region}",
    "5. Access Firebase Studio workspace: ${var.enable_firebase_hosting ? "https://${google_firebase_hosting_site.dev_workspace[0].site_id}.web.app" : "Set up Firebase Hosting first"}",
    "6. View monitoring dashboard: ${var.enable_monitoring ? "https://console.cloud.google.com/monitoring?project=${var.project_id}" : "Enable monitoring first"}",
    "7. Access Vertex AI Workbench: ${var.enable_vertex_ai ? "https://console.cloud.google.com/vertex-ai/workbench?project=${var.project_id}" : "Enable Vertex AI first"}"
  ]
}