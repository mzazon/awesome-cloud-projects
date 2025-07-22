# Outputs for QA Workflows Infrastructure
# These outputs provide important information for verification, integration, and management

# Project and basic configuration outputs
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = local.project_id
}

output "region" {
  description = "The primary region where resources are deployed"
  value       = local.region
}

output "environment" {
  description = "The environment tag applied to resources"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.random_suffix
}

# Storage outputs
output "qa_artifacts_bucket_name" {
  description = "Name of the Cloud Storage bucket for QA artifacts"
  value       = google_storage_bucket.qa_artifacts.name
}

output "qa_artifacts_bucket_url" {
  description = "URL of the Cloud Storage bucket for QA artifacts"
  value       = google_storage_bucket.qa_artifacts.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for Cloud Function source code"
  value       = google_storage_bucket.function_source.name
}

# Cloud Tasks outputs
output "qa_orchestration_queue_name" {
  description = "Name of the main QA orchestration queue"
  value       = google_cloud_tasks_queue.qa_orchestration.name
}

output "qa_priority_queue_name" {
  description = "Name of the priority QA tasks queue"
  value       = google_cloud_tasks_queue.qa_priority.name
}

output "qa_analysis_queue_name" {
  description = "Name of the AI analysis tasks queue"
  value       = google_cloud_tasks_queue.qa_analysis.name
}

output "task_queues_location" {
  description = "Location of the Cloud Tasks queues"
  value       = local.region
}

# Firebase and Firestore outputs
output "firebase_project_id" {
  description = "Firebase project identifier"
  value       = google_firebase_project.default.project
}

output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.database.name
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.database.location_id
}

output "firestore_collection_name" {
  description = "Name of the main Firestore collection for QA workflows"
  value       = local.firestore_collection
}

# Cloud Functions outputs
output "qa_phase_executor_function_name" {
  description = "Name of the QA phase executor Cloud Function"
  value       = google_cloudfunctions2_function.qa_phase_executor.name
}

output "qa_phase_executor_function_url" {
  description = "HTTP trigger URL for the QA phase executor Cloud Function"
  value       = google_cloudfunctions2_function.qa_phase_executor.url
}

output "qa_functions_service_account_email" {
  description = "Email address of the service account used by QA Cloud Functions"
  value       = google_service_account.qa_functions.email
}

# Cloud Run outputs
output "qa_dashboard_service_name" {
  description = "Name of the QA Dashboard Cloud Run service"
  value       = google_cloud_run_v2_service.qa_dashboard.name
}

output "qa_dashboard_url" {
  description = "URL of the QA Dashboard web interface"
  value       = google_cloud_run_v2_service.qa_dashboard.uri
}

output "qa_dashboard_service_account_email" {
  description = "Email address of the service account used by the QA Dashboard"
  value       = google_service_account.qa_dashboard.email
}

# Vertex AI outputs
output "vertex_ai_dataset_name" {
  description = "Name of the Vertex AI dataset for QA metrics"
  value       = google_vertex_ai_dataset.qa_metrics.name
}

output "vertex_ai_dataset_id" {
  description = "ID of the Vertex AI dataset for QA metrics"
  value       = google_vertex_ai_dataset.qa_metrics.display_name
}

output "vertex_ai_region" {
  description = "Region where Vertex AI resources are deployed"
  value       = local.region
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for QA analysis"
  value       = google_bigquery_dataset.qa_analysis.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.qa_analysis.location
}

output "bigquery_workflow_metrics_table_id" {
  description = "ID of the BigQuery table for workflow metrics"
  value       = google_bigquery_table.workflow_metrics.table_id
}

output "bigquery_table_full_name" {
  description = "Full name of the BigQuery workflow metrics table (project.dataset.table)"
  value       = "${local.project_id}.${google_bigquery_dataset.qa_analysis.dataset_id}.${google_bigquery_table.workflow_metrics.table_id}"
}

# Monitoring outputs
output "monitoring_alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy for QA workflow failures"
  value       = google_monitoring_alert_policy.qa_workflow_failures.name
}

output "monitoring_alert_policy_id" {
  description = "ID of the Cloud Monitoring alert policy"
  value       = google_monitoring_alert_policy.qa_workflow_failures.id
}

# App Engine outputs
output "app_engine_application_id" {
  description = "ID of the App Engine application (required for Cloud Tasks)"
  value       = google_app_engine_application.app.app_id
}

output "app_engine_location" {
  description = "Location of the App Engine application"
  value       = google_app_engine_application.app.location_id
}

# API endpoints and integration information
output "firestore_web_api_key" {
  description = "Web API key for Firebase client SDK integration (if needed)"
  value       = "Configure in Firebase Console for client-side access"
  sensitive   = false
}

output "cloud_tasks_queue_paths" {
  description = "Full resource paths for Cloud Tasks queues"
  value = {
    orchestration = "projects/${local.project_id}/locations/${local.region}/queues/${google_cloud_tasks_queue.qa_orchestration.name}"
    priority      = "projects/${local.project_id}/locations/${local.region}/queues/${google_cloud_tasks_queue.qa_priority.name}"
    analysis      = "projects/${local.project_id}/locations/${local.region}/queues/${google_cloud_tasks_queue.qa_analysis.name}"
  }
}

# Configuration for external integrations
output "integration_endpoints" {
  description = "Key endpoints for external system integration"
  value = {
    qa_function_url      = google_cloudfunctions2_function.qa_phase_executor.url
    dashboard_url        = google_cloud_run_v2_service.qa_dashboard.uri
    storage_bucket       = "gs://${google_storage_bucket.qa_artifacts.name}"
    firestore_project_id = local.project_id
    bigquery_table       = "${local.project_id}.${google_bigquery_dataset.qa_analysis.dataset_id}.${google_bigquery_table.workflow_metrics.table_id}"
  }
}

# Resource identifiers for management scripts
output "resource_identifiers" {
  description = "Resource identifiers for management and cleanup scripts"
  value = {
    project_id        = local.project_id
    region           = local.region
    random_suffix    = local.random_suffix
    bucket_names = [
      google_storage_bucket.qa_artifacts.name,
      google_storage_bucket.function_source.name
    ]
    queue_names = [
      google_cloud_tasks_queue.qa_orchestration.name,
      google_cloud_tasks_queue.qa_priority.name,
      google_cloud_tasks_queue.qa_analysis.name
    ]
    function_names = [
      google_cloudfunctions2_function.qa_phase_executor.name
    ]
    cloud_run_services = [
      google_cloud_run_v2_service.qa_dashboard.name
    ]
    service_accounts = [
      google_service_account.qa_functions.email,
      google_service_account.qa_dashboard.email
    ]
  }
}

# Cost optimization information
output "cost_optimization_info" {
  description = "Information about cost optimization features enabled"
  value = {
    storage_lifecycle_enabled = true
    nearline_transition_days  = var.storage_lifecycle_nearline_age
    coldline_transition_days  = var.storage_lifecycle_coldline_age
    deletion_days            = var.storage_lifecycle_delete_age
    uniform_bucket_access    = var.enable_uniform_bucket_level_access
    versioning_enabled       = var.enable_versioning
    cloud_run_min_instances  = 0
    function_min_instances   = 0
  }
}

# Security configuration summary
output "security_configuration" {
  description = "Summary of security configurations applied"
  value = {
    uniform_bucket_access     = var.enable_uniform_bucket_level_access
    service_account_isolation = true
    least_privilege_iam      = true
    firestore_rules_enabled  = true
    https_only_endpoints     = true
    private_function_access  = false
  }
}

# Next steps and instructions
output "next_steps" {
  description = "Next steps after infrastructure deployment"
  value = [
    "1. Access the QA Dashboard at: ${google_cloud_run_v2_service.qa_dashboard.uri}",
    "2. Configure notification channels in Cloud Monitoring for alerts",
    "3. Upload initial test data to: gs://${google_storage_bucket.qa_artifacts.name}",
    "4. Test the QA workflow by sending a POST request to: ${google_cloudfunctions2_function.qa_phase_executor.url}",
    "5. Monitor workflow execution in the Firestore console",
    "6. Review BigQuery analytics at: https://console.cloud.google.com/bigquery?project=${local.project_id}",
    "7. Configure Firebase Extensions for automatic workflow triggers",
    "8. Set up CI/CD integration using the provided endpoints"
  ]
}