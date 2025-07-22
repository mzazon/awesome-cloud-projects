# Healthcare API Outputs
output "healthcare_dataset_id" {
  description = "ID of the Healthcare dataset"
  value       = google_healthcare_dataset.healthcare_dataset.id
}

output "healthcare_dataset_name" {
  description = "Name of the Healthcare dataset"
  value       = google_healthcare_dataset.healthcare_dataset.name
}

output "fhir_store_id" {
  description = "ID of the FHIR store"
  value       = google_healthcare_fhir_store.fhir_store.id
}

output "fhir_store_name" {
  description = "Name of the FHIR store"
  value       = google_healthcare_fhir_store.fhir_store.name
}

output "fhir_store_endpoint" {
  description = "Base URL for FHIR store API endpoints"
  value       = "https://healthcare.googleapis.com/v1/${google_healthcare_fhir_store.fhir_store.id}/fhir"
}

# Pub/Sub Outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for FHIR changes"
  value       = google_pubsub_topic.fhir_changes.name
}

output "pubsub_topic_id" {
  description = "ID of the Pub/Sub topic for FHIR changes"
  value       = google_pubsub_topic.fhir_changes.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for FHIR events"
  value       = google_pubsub_subscription.fhir_events_subscription.name
}

output "pubsub_subscription_id" {
  description = "ID of the Pub/Sub subscription for FHIR events"
  value       = google_pubsub_subscription.fhir_events_subscription.id
}

# Cloud Storage Outputs
output "compliance_bucket_name" {
  description = "Name of the Cloud Storage bucket for compliance artifacts"
  value       = google_storage_bucket.compliance_bucket.name
}

output "compliance_bucket_url" {
  description = "URL of the Cloud Storage bucket for compliance artifacts"
  value       = google_storage_bucket.compliance_bucket.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

# Cloud Tasks Outputs
output "cloud_tasks_queue_name" {
  description = "Name of the Cloud Tasks queue for compliance processing"
  value       = google_cloud_tasks_queue.compliance_queue.name
}

output "cloud_tasks_queue_id" {
  description = "ID of the Cloud Tasks queue for compliance processing"
  value       = google_cloud_tasks_queue.compliance_queue.id
}

# BigQuery Outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for compliance analytics"
  value       = google_bigquery_dataset.compliance_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset for compliance analytics"
  value       = google_bigquery_dataset.compliance_dataset.location
}

output "compliance_events_table_id" {
  description = "ID of the compliance events BigQuery table"
  value       = google_bigquery_table.compliance_events.table_id
}

output "audit_trail_table_id" {
  description = "ID of the audit trail BigQuery table"
  value       = google_bigquery_table.audit_trail.table_id
}

# Cloud Functions Outputs
output "compliance_processor_function_name" {
  description = "Name of the compliance processor Cloud Function"
  value       = google_cloudfunctions_function.compliance_processor.name
}

output "compliance_processor_function_url" {
  description = "Trigger URL of the compliance processor Cloud Function"
  value       = google_cloudfunctions_function.compliance_processor.https_trigger_url
}

output "compliance_audit_function_name" {
  description = "Name of the compliance audit Cloud Function"
  value       = google_cloudfunctions_function.compliance_audit.name
}

output "compliance_audit_function_url" {
  description = "Trigger URL of the compliance audit Cloud Function"
  value       = google_cloudfunctions_function.compliance_audit.https_trigger_url
}

# Service Account Outputs
output "compliance_function_service_account_email" {
  description = "Email of the service account used by compliance functions"
  value       = google_service_account.compliance_function_sa.email
}

output "compliance_function_service_account_id" {
  description = "ID of the service account used by compliance functions"
  value       = google_service_account.compliance_function_sa.id
}

# Monitoring Outputs
output "monitoring_notification_channel_name" {
  description = "Name of the monitoring notification channel"
  value       = var.enable_monitoring_alerts ? google_monitoring_notification_channel.compliance_email[0].name : null
}

output "monitoring_alert_policy_name" {
  description = "Name of the high-risk events alert policy"
  value       = var.enable_monitoring_alerts ? google_monitoring_alert_policy.high_risk_events[0].name : null
}

# Configuration Outputs
output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.resource_suffix
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Resource URLs for Easy Access
output "fhir_store_console_url" {
  description = "Google Cloud Console URL for the FHIR store"
  value       = "https://console.cloud.google.com/healthcare/browser/datasets/${google_healthcare_dataset.healthcare_dataset.name}/fhirStores/${google_healthcare_fhir_store.fhir_store.name}?project=${var.project_id}"
}

output "bigquery_console_url" {
  description = "Google Cloud Console URL for the BigQuery dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.compliance_dataset.dataset_id}"
}

output "cloud_functions_console_url" {
  description = "Google Cloud Console URL for Cloud Functions"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

output "cloud_storage_console_url" {
  description = "Google Cloud Console URL for the compliance bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.compliance_bucket.name}?project=${var.project_id}"
}

# Example Commands for Testing
output "example_fhir_create_command" {
  description = "Example curl command to create a FHIR Patient resource"
  value = <<-EOT
    curl -X POST "${google_healthcare_fhir_store.fhir_store.id}/fhir/Patient" \
      -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      -H "Content-Type: application/fhir+json" \
      -d '{
        "resourceType": "Patient",
        "id": "test-patient-001",
        "name": [{"family": "Doe", "given": ["John"]}],
        "gender": "male",
        "birthDate": "1990-01-01"
      }'
  EOT
}

output "example_bigquery_query" {
  description = "Example BigQuery query to check compliance events"
  value = "SELECT COUNT(*) as event_count FROM `${var.project_id}.${google_bigquery_dataset.compliance_dataset.dataset_id}.compliance_events`"
}

output "example_pubsub_test_command" {
  description = "Example command to test Pub/Sub message processing"
  value = <<-EOT
    gcloud pubsub topics publish ${google_pubsub_topic.fhir_changes.name} \
      --message='{"resourceName":"Patient/test-patient-001","eventType":"CREATE","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}'
  EOT
}