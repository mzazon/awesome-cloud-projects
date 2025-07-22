# Healthcare Data Processing Infrastructure Outputs
# These outputs provide important information about the deployed resources

# Cloud Storage Outputs
output "healthcare_bucket_name" {
  description = "Name of the HIPAA-compliant healthcare data storage bucket"
  value       = google_storage_bucket.healthcare_data.name
}

output "healthcare_bucket_url" {
  description = "URL of the healthcare data storage bucket"
  value       = google_storage_bucket.healthcare_data.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Function source code bucket"
  value       = google_storage_bucket.function_source.name
}

# Healthcare API Outputs
output "healthcare_dataset_id" {
  description = "ID of the healthcare dataset"
  value       = google_healthcare_dataset.healthcare_dataset.id
}

output "healthcare_dataset_name" {
  description = "Name of the healthcare dataset"
  value       = google_healthcare_dataset.healthcare_dataset.name
}

output "fhir_store_id" {
  description = "ID of the FHIR store for patient records"
  value       = google_healthcare_fhir_store.patient_records.id
}

output "fhir_store_name" {
  description = "Name of the FHIR store"
  value       = google_healthcare_fhir_store.patient_records.name
}

output "fhir_store_version" {
  description = "FHIR version of the store"
  value       = google_healthcare_fhir_store.patient_records.version
}

# Service Account Outputs
output "healthcare_ai_agent_email" {
  description = "Email address of the healthcare AI agent service account"
  value       = google_service_account.healthcare_ai_agent.email
}

output "healthcare_ai_agent_unique_id" {
  description = "Unique ID of the healthcare AI agent service account"
  value       = google_service_account.healthcare_ai_agent.unique_id
}

output "function_service_account_email" {
  description = "Email address of the Cloud Function service account"
  value       = google_service_account.function_sa.email
}

# Cloud Function Outputs
output "cloud_function_name" {
  description = "Name of the healthcare processing Cloud Function"
  value       = google_cloudfunctions2_function.healthcare_processor.name
}

output "cloud_function_url" {
  description = "URL of the healthcare processing Cloud Function"
  value       = google_cloudfunctions2_function.healthcare_processor.service_config[0].uri
}

output "cloud_function_trigger_bucket" {
  description = "Storage bucket that triggers the Cloud Function"
  value       = google_storage_bucket.healthcare_data.name
}

# Pub/Sub Outputs
output "fhir_notifications_topic" {
  description = "Pub/Sub topic for FHIR store notifications"
  value       = google_pubsub_topic.fhir_notifications.name
}

output "fhir_notifications_topic_id" {
  description = "ID of the FHIR notifications topic"
  value       = google_pubsub_topic.fhir_notifications.id
}

# Monitoring Outputs
output "monitoring_dashboard_id" {
  description = "ID of the healthcare monitoring dashboard"
  value       = google_monitoring_dashboard.healthcare_dashboard.id
}

output "compliance_alert_policy_name" {
  description = "Name of the HIPAA compliance alert policy"
  value       = google_monitoring_alert_policy.compliance_alert.name
}

output "batch_failure_alert_policy_name" {
  description = "Name of the batch job failure alert policy"
  value       = google_monitoring_alert_policy.batch_failure_alert.name
}

# BigQuery Outputs
output "healthcare_analytics_dataset_id" {
  description = "ID of the BigQuery dataset for healthcare analytics"
  value       = google_bigquery_dataset.healthcare_analytics.dataset_id
}

output "healthcare_analytics_dataset_location" {
  description = "Location of the BigQuery analytics dataset"
  value       = google_bigquery_dataset.healthcare_analytics.location
}

# Audit and Logging Outputs
output "audit_log_sink_name" {
  description = "Name of the healthcare audit log sink"
  value       = google_logging_project_sink.healthcare_audit_sink.name
}

output "audit_log_sink_destination" {
  description = "Destination of the healthcare audit log sink"
  value       = google_logging_project_sink.healthcare_audit_sink.destination
}

output "audit_log_sink_writer_identity" {
  description = "Writer identity for the audit log sink"
  value       = google_logging_project_sink.healthcare_audit_sink.writer_identity
  sensitive   = true
}

# Configuration Outputs
output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Deployment region"
  value       = var.region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# API Service Outputs
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value = [
    google_project_service.healthcare.service,
    google_project_service.batch.service,
    google_project_service.aiplatform.service,
    google_project_service.storage.service,
    google_project_service.cloudfunctions.service,
    google_project_service.cloudbuild.service,
    google_project_service.eventarc.service,
    google_project_service.monitoring.service,
    google_project_service.logging.service
  ]
}

# Security and Compliance Outputs
output "storage_bucket_labels" {
  description = "Labels applied to the healthcare storage bucket for compliance tracking"
  value       = google_storage_bucket.healthcare_data.labels
}

output "healthcare_dataset_labels" {
  description = "Labels applied to the healthcare dataset for compliance tracking"
  value       = google_healthcare_dataset.healthcare_dataset.labels
}

output "bucket_versioning_enabled" {
  description = "Whether versioning is enabled on the healthcare data bucket"
  value       = google_storage_bucket.healthcare_data.versioning[0].enabled
}

output "uniform_bucket_level_access_enabled" {
  description = "Whether uniform bucket-level access is enabled for enhanced security"
  value       = google_storage_bucket.healthcare_data.uniform_bucket_level_access
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Instructions for using the deployed healthcare processing infrastructure"
  value = <<-EOT
    Healthcare Data Processing Infrastructure Deployed Successfully!
    
    Getting Started:
    1. Upload medical records to: gs://${google_storage_bucket.healthcare_data.name}
    2. Files will automatically trigger processing via Cloud Function: ${google_cloudfunctions2_function.healthcare_processor.name}
    3. Monitor processing through dashboard: ${google_monitoring_dashboard.healthcare_dashboard.id}
    4. View FHIR-compliant results in dataset: ${google_healthcare_dataset.healthcare_dataset.name}
    
    HIPAA Compliance Features:
    - Audit logging enabled for all healthcare data access
    - Data retention configured for 7+ years
    - Encryption at rest and in transit
    - Access controls via IAM service accounts
    
    Monitoring and Alerts:
    - Compliance violations: ${google_monitoring_alert_policy.compliance_alert.name}
    - Batch job failures: ${google_monitoring_alert_policy.batch_failure_alert.name}
    
    Next Steps:
    1. Configure notification channels for alerts
    2. Upload sample healthcare data for testing
    3. Review audit logs in BigQuery: ${google_bigquery_dataset.healthcare_analytics.dataset_id}
    4. Customize Vertex AI agent processing logic
    
    Important Security Notes:
    - All service accounts follow least privilege principle
    - Healthcare data bucket has versioning enabled
    - FHIR store configured with R4 compliance
    - Comprehensive audit logging to BigQuery
  EOT
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs while maintaining compliance"
  value = <<-EOT
    Cost Optimization Recommendations:
    
    1. Storage Lifecycle:
       - Data automatically transitions to COLDLINE after 1 year
       - Consider ARCHIVE class for long-term retention beyond 7 years
    
    2. Cloud Function:
       - Configured with minimum instances: 0 (pay-per-use)
       - Timeout set to ${var.function_timeout_seconds}s to prevent overruns
    
    3. Batch Processing:
       - Uses e2-standard-2 machines (cost-optimized)
       - Jobs have max runtime limit to prevent runaway costs
    
    4. Monitoring:
       - Basic monitoring included, consider upgrading for larger workloads
       - Alert policies prevent resource waste from failures
    
    5. BigQuery:
       - Audit logs in BigQuery - monitor query costs
       - Consider partitioning for large audit datasets
  EOT
}

# Compliance and Security Summary
output "compliance_features" {
  description = "Summary of HIPAA compliance features implemented"
  value = {
    encryption = {
      at_rest     = "Google-managed encryption keys (GMEK)"
      in_transit  = "TLS 1.2+ for all API communications"
      fhir_store  = "Healthcare API encryption"
    }
    access_control = {
      iam_service_accounts = "Least privilege principle"
      bucket_iam          = "Object-level access controls"
      healthcare_api      = "FHIR-specific access controls"
    }
    audit_logging = {
      storage_access      = "All bucket operations logged"
      healthcare_access   = "All FHIR operations logged"
      function_execution  = "Cloud Function logs"
      batch_jobs         = "Batch job execution logs"
    }
    data_retention = {
      healthcare_data = "${var.healthcare_data_retention_days} days (${var.healthcare_data_retention_days / 365} years)"
      audit_logs     = "Indefinite (configurable in BigQuery)"
      fhir_versioning = var.enable_fhir_versioning
    }
    monitoring = {
      compliance_alerts = "Real-time HIPAA violation detection"
      operational_alerts = "Batch job failure notifications"
      dashboard         = "Healthcare processing metrics"
    }
  }
}