# ============================================================================
# OUTPUTS
# ============================================================================

# Project Information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for AML compliance data"
  value       = google_bigquery_dataset.aml_compliance.dataset_id
}

output "bigquery_dataset_location" {
  description = "BigQuery dataset location"
  value       = google_bigquery_dataset.aml_compliance.location
}

output "transactions_table_id" {
  description = "BigQuery transactions table ID"
  value       = google_bigquery_table.transactions.table_id
}

output "transactions_table_full_id" {
  description = "Full BigQuery transactions table ID for queries"
  value       = "${var.project_id}.${google_bigquery_dataset.aml_compliance.dataset_id}.${google_bigquery_table.transactions.table_id}"
}

output "compliance_alerts_table_id" {
  description = "BigQuery compliance alerts table ID"
  value       = google_bigquery_table.compliance_alerts.table_id
}

output "compliance_alerts_table_full_id" {
  description = "Full BigQuery compliance alerts table ID for queries"
  value       = "${var.project_id}.${google_bigquery_dataset.aml_compliance.dataset_id}.${google_bigquery_table.compliance_alerts.table_id}"
}

output "ml_model_id" {
  description = "BigQuery ML model ID for AML detection"
  value       = var.ml_model_id
}

output "ml_model_full_id" {
  description = "Full BigQuery ML model ID for predictions"
  value       = "${var.project_id}.${google_bigquery_dataset.aml_compliance.dataset_id}.${var.ml_model_id}"
}

# Cloud Storage Resources
output "compliance_reports_bucket_name" {
  description = "Cloud Storage bucket name for compliance reports"
  value       = google_storage_bucket.compliance_reports.name
}

output "compliance_reports_bucket_url" {
  description = "Cloud Storage bucket URL for compliance reports"
  value       = google_storage_bucket.compliance_reports.url
}

output "function_source_bucket_name" {
  description = "Cloud Storage bucket name for function source code"
  value       = google_storage_bucket.function_source.name
}

# Pub/Sub Resources
output "pubsub_topic_name" {
  description = "Pub/Sub topic name for AML alerts"
  value       = google_pubsub_topic.aml_alerts.name
}

output "pubsub_topic_id" {
  description = "Full Pub/Sub topic ID"
  value       = google_pubsub_topic.aml_alerts.id
}

output "pubsub_subscription_name" {
  description = "Pub/Sub subscription name for AML alerts"
  value       = google_pubsub_subscription.aml_alerts.name
}

output "pubsub_subscription_id" {
  description = "Full Pub/Sub subscription ID"
  value       = google_pubsub_subscription.aml_alerts.id
}

output "pubsub_dead_letter_topic_name" {
  description = "Pub/Sub dead letter topic name"
  value       = google_pubsub_topic.aml_alerts_dlq.name
}

# Cloud Functions
output "alert_processor_function_name" {
  description = "Name of the alert processing Cloud Function"
  value       = google_cloudfunctions2_function.alert_processor.name
}

output "alert_processor_function_url" {
  description = "URL of the alert processing Cloud Function"
  value       = google_cloudfunctions2_function.alert_processor.service_config[0].uri
}

output "report_generator_function_name" {
  description = "Name of the compliance report generation Cloud Function"
  value       = google_cloudfunctions2_function.report_generator.name
}

output "report_generator_function_url" {
  description = "URL of the compliance report generation Cloud Function"
  value       = google_cloudfunctions2_function.report_generator.service_config[0].uri
}

# Cloud Scheduler
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for compliance reporting"
  value       = google_cloud_scheduler_job.compliance_report.name
}

output "scheduler_job_schedule" {
  description = "Schedule for the compliance reporting job"
  value       = google_cloud_scheduler_job.compliance_report.schedule
}

output "scheduler_job_timezone" {
  description = "Timezone for the compliance reporting job"
  value       = google_cloud_scheduler_job.compliance_report.time_zone
}

# Security and Encryption
output "kms_key_ring_id" {
  description = "KMS key ring ID for encryption (if enabled)"
  value       = var.enable_encryption ? google_kms_key_ring.compliance[0].id : null
}

output "kms_crypto_key_id" {
  description = "KMS crypto key ID for bucket encryption (if enabled)"
  value       = var.enable_encryption ? google_kms_crypto_key.bucket_key[0].id : null
}

# Monitoring
output "monitoring_notification_channel_id" {
  description = "Monitoring notification channel ID (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.email[0].id : null
}

output "function_failures_alert_policy_id" {
  description = "Alert policy ID for function failures (if monitoring enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_failures[0].name : null
}

output "high_risk_transactions_alert_policy_id" {
  description = "Alert policy ID for high-risk transactions (if monitoring enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.high_risk_transactions[0].name : null
}

# Resource Names with Random Suffix
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# IAM and Service Accounts
output "function_service_account_email" {
  description = "Service account email used by Cloud Functions"
  value       = local.function_service_account
}

# API Services
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = var.enable_apis
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed AML compliance system"
  value = {
    test_ml_model = "bq query --use_legacy_sql=false \"SELECT * FROM ML.PREDICT(MODEL \\`${var.project_id}.${google_bigquery_dataset.aml_compliance.dataset_id}.${var.ml_model_id}\\`, (SELECT 75000.0 as amount, 0.85 as risk_score, 1 as is_wire_transfer, 1 as is_high_risk_country))\""
    
    publish_test_alert = "echo '{\"transaction_id\":\"TEST001\",\"risk_score\":0.9,\"project_id\":\"${var.project_id}\",\"dataset\":\"${google_bigquery_dataset.aml_compliance.dataset_id}\"}' | gcloud pubsub topics publish ${google_pubsub_topic.aml_alerts.name} --message=-"
    
    trigger_report_manually = "gcloud scheduler jobs run ${google_cloud_scheduler_job.compliance_report.name} --location=${var.region}"
    
    view_compliance_reports = "gsutil ls gs://${google_storage_bucket.compliance_reports.name}/compliance-reports/"
    
    check_alerts_table = "bq query --use_legacy_sql=false \"SELECT COUNT(*) as alert_count FROM \\`${var.project_id}.${google_bigquery_dataset.aml_compliance.dataset_id}.${google_bigquery_table.compliance_alerts.table_id}\\`\""
    
    view_function_logs_alert = "gcloud functions logs read ${google_cloudfunctions2_function.alert_processor.name} --gen2 --limit=10"
    
    view_function_logs_report = "gcloud functions logs read ${google_cloudfunctions2_function.report_generator.name} --gen2 --limit=10"
  }
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the AML compliance system"
  value = {
    bigquery_partitioning = "Tables are partitioned by timestamp and clustered by country_code and transaction_type for query optimization"
    storage_lifecycle = "Cloud Storage bucket has lifecycle rules to move data to cheaper storage classes over time"
    function_memory = "Adjust function memory allocation based on actual usage patterns"
    monitoring_alerts = "Use monitoring alerts to detect and respond to cost spikes quickly"
    scheduled_reporting = "Compliance reports run daily at 2 AM to minimize costs during peak hours"
  }
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for the AML compliance system"
  value = {
    iam_permissions = "Review and restrict IAM permissions to minimum required for operations"
    data_encryption = "Enable customer-managed encryption keys for additional security"
    network_security = "Configure VPC service controls for additional network security"
    audit_logging = "Enable Cloud Audit Logs for comprehensive security monitoring"
    access_controls = "Implement principle of least privilege for all service accounts"
    data_classification = "Classify and label sensitive financial data appropriately"
  }
}

# Compliance Features
output "compliance_features" {
  description = "Features that support regulatory compliance"
  value = {
    audit_trails = "Comprehensive audit trails maintained in BigQuery and Cloud Audit Logs"
    data_retention = "Configurable data retention policies for compliance requirements"
    encryption = "Data encrypted at rest and in transit"
    access_logging = "All data access logged and monitored"
    automated_reporting = "Automated compliance report generation and storage"
    alerting = "Real-time alerting for suspicious activities"
    ml_explainability = "BigQuery ML provides explainable AI results for regulatory review"
  }
}