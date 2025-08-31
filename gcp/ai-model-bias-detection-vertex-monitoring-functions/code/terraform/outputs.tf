# Outputs for AI Model Bias Detection Infrastructure

# Project Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = data.google_project.current.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Cloud Storage
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for bias detection artifacts"
  value       = google_storage_bucket.bias_detection_bucket.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.bias_detection_bucket.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.bias_detection_bucket.self_link
}

# Pub/Sub Resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for model monitoring alerts"
  value       = google_pubsub_topic.model_monitoring_alerts.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.model_monitoring_alerts.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for bias detection"
  value       = google_pubsub_subscription.bias_detection_sub.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.bias_detection_sub.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed message processing"
  value       = google_pubsub_topic.dead_letter_topic.name
}

# Service Account
output "function_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "function_service_account_id" {
  description = "ID of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.account_id
}

# Cloud Functions
output "bias_detection_function_name" {
  description = "Name of the bias detection Cloud Function"
  value       = google_cloudfunctions2_function.bias_detection_function.name
}

output "bias_detection_function_url" {
  description = "URL of the bias detection Cloud Function"
  value       = google_cloudfunctions2_function.bias_detection_function.service_config[0].uri
}

output "alert_processing_function_name" {
  description = "Name of the alert processing Cloud Function"
  value       = google_cloudfunctions2_function.alert_processing_function.name
}

output "alert_processing_function_url" {
  description = "URL of the alert processing Cloud Function"
  value       = google_cloudfunctions2_function.alert_processing_function.service_config[0].uri
}

output "audit_function_name" {
  description = "Name of the audit report generation Cloud Function"
  value       = google_cloudfunctions2_function.audit_function.name
}

output "audit_function_url" {
  description = "URL of the audit report generation Cloud Function"
  value       = google_cloudfunctions2_function.audit_function.service_config[0].uri
}

# Cloud Scheduler
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for bias audits"
  value       = google_cloud_scheduler_job.bias_audit_scheduler.name
}

output "scheduler_job_id" {
  description = "Full resource ID of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.bias_audit_scheduler.id
}

output "audit_schedule" {
  description = "Cron schedule for bias audit execution"
  value       = google_cloud_scheduler_job.bias_audit_scheduler.schedule
}

output "audit_timezone" {
  description = "Timezone for audit schedule execution"
  value       = google_cloud_scheduler_job.bias_audit_scheduler.time_zone
}

# BigQuery (if enabled)
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for bias detection logs"
  value       = var.enable_bigquery_export ? google_bigquery_dataset.bias_logs.dataset_id : null
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = var.enable_bigquery_export ? google_bigquery_dataset.bias_logs.location : null
}

output "log_sink_name" {
  description = "Name of the log sink for bias detection events"
  value       = var.enable_bigquery_export ? google_logging_project_sink.bias_detection_sink.name : null
}

output "log_sink_writer_identity" {
  description = "Writer identity of the log sink (for BigQuery permissions)"
  value       = var.enable_bigquery_export ? google_logging_project_sink.bias_detection_sink.writer_identity : null
}

# Monitoring
output "monitoring_alert_policy_name" {
  description = "Name of the monitoring alert policy for critical bias violations"
  value       = var.enable_monitoring_alerts ? google_monitoring_alert_policy.critical_bias_alert.display_name : null
}

# Configuration Information
output "bias_thresholds" {
  description = "Configured bias detection thresholds"
  value       = var.bias_thresholds
}

output "alert_severity_thresholds" {
  description = "Configured alert severity thresholds"
  value       = var.alert_severity_thresholds
}

output "function_memory_allocations" {
  description = "Memory allocations for Cloud Functions"
  value       = var.function_memory_mb
}

output "function_timeout_settings" {
  description = "Timeout settings for Cloud Functions"
  value       = var.function_timeout_seconds
}

# URLs for Testing and Integration
output "test_commands" {
  description = "Commands for testing the bias detection system"
  value = {
    test_bias_detection = "gcloud pubsub topics publish ${google_pubsub_topic.model_monitoring_alerts.name} --message='{\"model_name\": \"test-model\", \"drift_metric\": 0.12, \"alert_type\": \"drift\", \"timestamp\": \"'$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")'\"}}'"
    
    test_alert_processing = "curl -X POST '${google_cloudfunctions2_function.alert_processing_function.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"bias_score\": 0.13, \"fairness_violations\": [\"Demographic parity violation\"], \"model_name\": \"test-model\", \"timestamp\": \"'$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")'\"]}'"
    
    test_audit_function = "curl -X POST '${google_cloudfunctions2_function.audit_function.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"audit_type\": \"manual\", \"trigger\": \"test\"}'"
    
    check_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.bias_detection_function.name} --gen2 --limit=10"
    
    list_reports = "gsutil ls gs://${google_storage_bucket.bias_detection_bucket.name}/reports/"
    
    check_compliance_logs = "gcloud logging read 'resource.type=\"cloud_function\" AND jsonPayload.message:\"COMPLIANCE_EVENT\"' --limit=5 --format='value(jsonPayload.message, timestamp)'"
  }
}

# Integration Endpoints
output "integration_endpoints" {
  description = "Endpoints for integrating with external systems"
  value = {
    bias_alert_webhook      = google_cloudfunctions2_function.alert_processing_function.service_config[0].uri
    manual_audit_trigger    = google_cloudfunctions2_function.audit_function.service_config[0].uri
    pubsub_topic_for_alerts = google_pubsub_topic.model_monitoring_alerts.id
    storage_bucket_for_reports = "gs://${google_storage_bucket.bias_detection_bucket.name}"
  }
}

# Resource Labels
output "applied_labels" {
  description = "Labels applied to resources for identification and management"
  value = merge(
    {
      purpose     = "bias-detection"
      environment = var.environment
      managed-by  = "terraform"
    },
    var.labels
  )
}

# Compliance and Governance
output "compliance_features" {
  description = "Enabled compliance and governance features"
  value = {
    audit_trail_enabled     = var.enable_audit_trail
    bigquery_export_enabled = var.enable_bigquery_export
    monitoring_alerts_enabled = var.enable_monitoring_alerts
    storage_versioning_enabled = true
    log_retention_days = var.log_retention_days
    compliance_reporting_frequency = var.compliance_reporting_frequency
  }
}

# Cost Optimization Information
output "cost_optimization_features" {
  description = "Cost optimization features enabled in the deployment"
  value = {
    storage_lifecycle_rules = var.storage_lifecycle_rules
    function_scaling_limits = var.max_function_instances
    log_export_to_bigquery = var.enable_bigquery_export
    scheduled_audit_frequency = var.audit_schedule
  }
}

# Security Configuration
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    service_account_email = google_service_account.function_sa.email
    uniform_bucket_access = true
    public_access_prevention = "enforced"
    vpc_connector_enabled = var.enable_vpc_connector
    private_google_access = var.enable_private_google_access
    function_ingress_settings = {
      bias_detection = "ALLOW_INTERNAL_ONLY"
      alert_processing = "ALLOW_ALL"
      audit_generation = "ALLOW_INTERNAL_ONLY"
    }
  }
}

# Next Steps and Recommendations
output "deployment_next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the bias detection system using the provided test commands",
    "2. Configure notification channels for monitoring alerts if not already done",
    "3. Set up Vertex AI Model Monitoring for your deployed models",
    "4. Review and adjust bias thresholds based on your specific requirements",
    "5. Integrate the alert webhook with your incident management system",
    "6. Set up dashboard visualization using the BigQuery dataset (if enabled)",
    "7. Configure backup and disaster recovery procedures for compliance data",
    "8. Review IAM permissions and adjust based on least privilege principle"
  ]
}

# Documentation and Support
output "documentation_links" {
  description = "Links to relevant documentation and support resources"
  value = {
    vertex_ai_monitoring = "https://cloud.google.com/vertex-ai/docs/model-monitoring"
    cloud_functions_docs = "https://cloud.google.com/functions/docs"
    responsible_ai_practices = "https://cloud.google.com/responsible-ai"
    cloud_logging_best_practices = "https://cloud.google.com/logging/docs/audit/best-practices"
    terraform_google_provider = "https://registry.terraform.io/providers/hashicorp/google/latest/docs"
  }
}