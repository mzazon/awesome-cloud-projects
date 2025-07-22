# Core infrastructure outputs
output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

# Healthcare API outputs
output "healthcare_dataset_id" {
  description = "Healthcare dataset ID for FHIR resources"
  value       = google_healthcare_dataset.patient_records.id
}

output "healthcare_dataset_name" {
  description = "Healthcare dataset name"
  value       = google_healthcare_dataset.patient_records.name
}

output "fhir_store_id" {
  description = "FHIR store ID for patient records"
  value       = google_healthcare_fhir_store.patient_fhir.id
}

output "fhir_store_name" {
  description = "FHIR store name"
  value       = google_healthcare_fhir_store.patient_fhir.name
}

output "fhir_store_version" {
  description = "FHIR version used in the store"
  value       = google_healthcare_fhir_store.patient_fhir.version
}

# Pub/Sub outputs
output "pubsub_topic_id" {
  description = "Pub/Sub topic ID for FHIR notifications"
  value       = google_pubsub_topic.fhir_notifications.id
}

output "pubsub_topic_name" {
  description = "Pub/Sub topic name"
  value       = google_pubsub_topic.fhir_notifications.name
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for sentiment analysis results"
  value       = google_bigquery_dataset.sentiment_analysis.dataset_id
}

output "bigquery_dataset_location" {
  description = "BigQuery dataset location"
  value       = google_bigquery_dataset.sentiment_analysis.location
}

output "bigquery_table_id" {
  description = "BigQuery table ID for sentiment analysis results"
  value       = google_bigquery_table.sentiment_results.table_id
}

output "bigquery_table_full_name" {
  description = "Full BigQuery table name for queries"
  value       = "${var.project_id}.${google_bigquery_dataset.sentiment_analysis.dataset_id}.${google_bigquery_table.sentiment_results.table_id}"
}

output "bigquery_summary_view" {
  description = "BigQuery summary view for sentiment analytics"
  value       = "${var.project_id}.${google_bigquery_dataset.sentiment_analysis.dataset_id}.${google_bigquery_table.sentiment_summary_view.table_id}"
}

# Cloud Function outputs
output "cloud_function_name" {
  description = "Cloud Function name for sentiment processing"
  value       = google_cloudfunctions2_function.sentiment_processor.name
}

output "cloud_function_url" {
  description = "Cloud Function URL (if HTTP trigger)"
  value       = google_cloudfunctions2_function.sentiment_processor.service_config[0].uri
}

output "cloud_function_service_account" {
  description = "Service account email for the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Storage outputs
output "function_source_bucket" {
  description = "Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# FHIR API endpoints for testing
output "fhir_base_url" {
  description = "Base URL for FHIR REST API operations"
  value       = "https://healthcare.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/datasets/${google_healthcare_dataset.patient_records.name}/fhirStores/${google_healthcare_fhir_store.patient_fhir.name}/fhir"
}

output "patient_endpoint" {
  description = "FHIR Patient resource endpoint"
  value       = "https://healthcare.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/datasets/${google_healthcare_dataset.patient_records.name}/fhirStores/${google_healthcare_fhir_store.patient_fhir.name}/fhir/Patient"
}

output "observation_endpoint" {
  description = "FHIR Observation resource endpoint"
  value       = "https://healthcare.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/datasets/${google_healthcare_dataset.patient_records.name}/fhirStores/${google_healthcare_fhir_store.patient_fhir.name}/fhir/Observation"
}

# Testing and validation commands
output "test_commands" {
  description = "Useful commands for testing the sentiment analysis pipeline"
  value = {
    # BigQuery query to view sentiment results
    view_results = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.sentiment_analysis.dataset_id}.${google_bigquery_table.sentiment_results.table_id}` ORDER BY processing_timestamp DESC LIMIT 10'"
    
    # Check function logs
    view_logs = "gcloud functions logs read ${google_cloudfunctions2_function.sentiment_processor.name} --region=${var.region} --limit=50"
    
    # Monitor Pub/Sub topic
    monitor_topic = "gcloud pubsub topics list-subscriptions ${google_pubsub_topic.fhir_notifications.name}"
    
    # View FHIR resources
    list_patients = "curl -H 'Authorization: Bearer $(gcloud auth print-access-token)' '${output.patient_endpoint.value}'"
    
    # Sentiment analysis summary
    view_summary = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.sentiment_analysis.dataset_id}.${google_bigquery_table.sentiment_summary_view.table_id}`'"
  }
}

# Sample FHIR patient record for testing
output "sample_patient_json" {
  description = "Sample FHIR patient record for testing"
  value = jsonencode({
    resourceType = "Patient"
    id          = "sample-patient-001"
    identifier = [{
      use    = "usual"
      system = "http://hospital.example.org"
      value  = "12345"
    }]
    name = [{
      use    = "official"
      family = "Smith"
      given  = ["John"]
    }]
    gender    = "male"
    birthDate = "1980-01-01"
  })
}

# Sample FHIR observation record for testing
output "sample_observation_json" {
  description = "Sample FHIR observation record with patient feedback for testing"
  value = jsonencode({
    resourceType = "Observation"
    id          = "sample-obs-001"
    status      = "final"
    category = [{
      coding = [{
        system  = "http://terminology.hl7.org/CodeSystem/observation-category"
        code    = "survey"
        display = "Survey"
      }]
    }]
    code = {
      coding = [{
        system  = "http://loinc.org"
        code    = "72133-2"
        display = "Patient satisfaction"
      }]
    }
    subject = {
      reference = "Patient/sample-patient-001"
    }
    valueString = "The staff was incredibly helpful and caring during my stay. The nurses were attentive and made me feel comfortable throughout the treatment process."
    note = [{
      text = "Patient expressed high satisfaction with nursing care and overall treatment experience. Mentioned feeling well-supported during recovery period."
    }]
  })
}

# Monitoring and alerting outputs
output "monitoring_dashboard_url" {
  description = "URL to view Cloud Function monitoring dashboard"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.sentiment_processor.name}?project=${var.project_id}&tab=monitoring"
}

output "bigquery_console_url" {
  description = "URL to BigQuery console for sentiment analysis dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.sentiment_analysis.dataset_id}"
}

output "healthcare_console_url" {
  description = "URL to Healthcare API console"
  value       = "https://console.cloud.google.com/healthcare/browser/${var.region}/${google_healthcare_dataset.patient_records.name}?project=${var.project_id}"
}

# Cost estimation guidance
output "cost_estimation" {
  description = "Estimated monthly costs for the sentiment analysis pipeline (USD)"
  value = {
    healthcare_api  = "~$0.50 per 1,000 FHIR operations"
    natural_language = "~$1.00 per 1,000 text records analyzed"
    cloud_functions = "~$0.40 per 1 million invocations + compute time"
    bigquery       = "~$5.00 per TB of data stored + $5.00 per TB queried"
    pubsub         = "~$0.40 per million messages"
    storage        = "~$0.20 per month for function source code"
    total_estimate = "~$15-25 per month for moderate usage (1,000 patient records)"
  }
}

# Security and compliance outputs
output "security_considerations" {
  description = "Important security and compliance considerations"
  value = {
    hipaa_compliance = "Healthcare API provides HIPAA-compliant infrastructure"
    encryption      = "All data encrypted in transit and at rest"
    access_control  = "IAM-based access control with least privilege principles"
    audit_logging   = "All API calls logged for compliance auditing"
    data_location   = "Data stored in specified region for data residency requirements"
  }
}

# Next steps and usage guidance
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    step1 = "Upload sample FHIR patient records using the provided JSON templates"
    step2 = "Create FHIR observation records with patient feedback text"
    step3 = "Monitor Cloud Function logs to verify sentiment analysis processing"
    step4 = "Query BigQuery table to view sentiment analysis results"
    step5 = "Create Looker Studio dashboard using BigQuery as data source"
    step6 = "Configure monitoring alerts for production use"
  }
}