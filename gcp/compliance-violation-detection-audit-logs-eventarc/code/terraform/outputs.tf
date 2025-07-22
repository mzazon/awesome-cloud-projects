# Outputs for GCP Compliance Violation Detection Terraform Configuration
# These outputs provide important information about the deployed compliance monitoring infrastructure

# Project and Location Information
output "project_id" {
  description = "The Google Cloud project ID where the compliance monitoring system is deployed"
  value       = local.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources are deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name used for resource labeling and configuration"
  value       = var.environment
}

# Cloud Function Information
output "compliance_function_name" {
  description = "Name of the Cloud Function that analyzes audit logs for compliance violations"
  value       = google_cloudfunctions2_function.compliance_detector.name
}

output "compliance_function_url" {
  description = "URL of the compliance detection Cloud Function for monitoring and debugging"
  value       = google_cloudfunctions2_function.compliance_detector.service_config[0].uri
}

output "compliance_function_service_account" {
  description = "Email of the service account used by the compliance detection function"
  value       = google_service_account.function_sa.email
}

output "function_logs_url" {
  description = "Direct URL to view Cloud Function logs in the Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.compliance_detector.name}/logs?project=${local.project_id}"
}

# Pub/Sub Resources
output "compliance_alerts_topic" {
  description = "Name of the Pub/Sub topic where compliance violation alerts are published"
  value       = google_pubsub_topic.compliance_alerts.name
}

output "compliance_alerts_topic_id" {
  description = "Full resource ID of the compliance alerts Pub/Sub topic"
  value       = google_pubsub_topic.compliance_alerts.id
}

output "compliance_alerts_subscription" {
  description = "Name of the Pub/Sub subscription for processing compliance alerts"
  value       = google_pubsub_subscription.compliance_alerts.name
}

output "dead_letter_topic" {
  description = "Name of the dead letter queue topic for unprocessable messages"
  value       = google_pubsub_topic.compliance_alerts_dlq.name
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset containing compliance violation data"
  value       = google_bigquery_dataset.compliance_logs.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset for compliance data"
  value       = google_bigquery_dataset.compliance_logs.location
}

output "violations_table_id" {
  description = "Full table ID for the violations table in BigQuery"
  value       = "${local.project_id}.${google_bigquery_dataset.compliance_logs.dataset_id}.${google_bigquery_table.violations.table_id}"
}

output "bigquery_console_url" {
  description = "Direct URL to view the compliance dataset in BigQuery console"
  value       = "https://console.cloud.google.com/bigquery?project=${local.project_id}&ws=!1m5!1m4!4m3!1s${local.project_id}!2s${google_bigquery_dataset.compliance_logs.dataset_id}!3sviolations"
}

# Logging and Monitoring Resources
output "log_sink_name" {
  description = "Name of the log sink routing audit logs to BigQuery"
  value       = google_logging_project_sink.compliance_audit_sink.name
}

output "log_sink_writer_identity" {
  description = "Service account used by the log sink to write to BigQuery"
  value       = google_logging_project_sink.compliance_audit_sink.writer_identity
}

output "compliance_metric_name" {
  description = "Name of the log-based metric tracking compliance violations"
  value       = google_logging_metric.compliance_violations.name
}

output "alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy for high-severity violations"
  value       = google_monitoring_alert_policy.high_severity_violations.display_name
}

output "monitoring_dashboard_url" {
  description = "Direct URL to view the compliance monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.compliance_monitoring.id}?project=${local.project_id}"
}

# Storage Resources
output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_object" {
  description = "Name of the source code object in Cloud Storage"
  value       = google_storage_bucket_object.function_source.name
}

# Compliance Monitoring URLs and Access Information
output "cloud_console_urls" {
  description = "Map of useful Google Cloud Console URLs for monitoring and managing the compliance system"
  value = {
    project_overview = "https://console.cloud.google.com/home/dashboard?project=${local.project_id}"
    
    # Function monitoring
    function_details    = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.compliance_detector.name}?project=${local.project_id}"
    function_logs      = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.compliance_detector.name}/logs?project=${local.project_id}"
    function_metrics   = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.compliance_detector.name}/metrics?project=${local.project_id}"
    
    # Data and analytics
    bigquery_dataset   = "https://console.cloud.google.com/bigquery?project=${local.project_id}&ws=!1m5!1m4!4m3!1s${local.project_id}!2s${google_bigquery_dataset.compliance_logs.dataset_id}!3sviolations"
    violations_table   = "https://console.cloud.google.com/bigquery?project=${local.project_id}&ws=!1m5!1m4!4m3!1s${local.project_id}!2s${google_bigquery_dataset.compliance_logs.dataset_id}!3sviolations"
    
    # Messaging
    pubsub_topic       = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.compliance_alerts.name}?project=${local.project_id}"
    pubsub_subscription = "https://console.cloud.google.com/cloudpubsub/subscription/detail/${google_pubsub_subscription.compliance_alerts.name}?project=${local.project_id}"
    
    # Monitoring and alerting
    monitoring_dashboard = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.compliance_monitoring.id}?project=${local.project_id}"
    alert_policies     = "https://console.cloud.google.com/monitoring/alerting/policies?project=${local.project_id}"
    logs_explorer      = "https://console.cloud.google.com/logs/query?project=${local.project_id}"
    
    # Security and access
    iam_policies       = "https://console.cloud.google.com/iam-admin/iam?project=${local.project_id}"
    audit_logs        = "https://console.cloud.google.com/logs/query;query=protoPayload.@type%3D%22type.googleapis.com%2Fgoogle.cloud.audit.AuditLog%22?project=${local.project_id}"
  }
}

# Sample Queries for BigQuery Analysis
output "sample_bigquery_queries" {
  description = "Sample BigQuery queries for analyzing compliance violations"
  value = {
    recent_violations = <<-EOT
      SELECT 
        timestamp,
        violation_type,
        severity,
        principal,
        resource,
        details
      FROM `${local.project_id}.${google_bigquery_dataset.compliance_logs.dataset_id}.violations`
      WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
      ORDER BY timestamp DESC
      LIMIT 100
    EOT
    
    violations_by_type = <<-EOT
      SELECT 
        violation_type,
        severity,
        COUNT(*) as violation_count,
        COUNT(DISTINCT principal) as unique_principals
      FROM `${local.project_id}.${google_bigquery_dataset.compliance_logs.dataset_id}.violations`
      WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
      GROUP BY violation_type, severity
      ORDER BY violation_count DESC
    EOT
    
    top_violating_principals = <<-EOT
      SELECT 
        principal,
        COUNT(*) as total_violations,
        COUNT(DISTINCT violation_type) as violation_types,
        MAX(timestamp) as last_violation
      FROM `${local.project_id}.${google_bigquery_dataset.compliance_logs.dataset_id}.violations`
      WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
      GROUP BY principal
      ORDER BY total_violations DESC
      LIMIT 20
    EOT
    
    compliance_trend = <<-EOT
      SELECT 
        DATE(timestamp) as violation_date,
        violation_type,
        severity,
        COUNT(*) as daily_count
      FROM `${local.project_id}.${google_bigquery_dataset.compliance_logs.dataset_id}.violations`
      WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
      GROUP BY violation_date, violation_type, severity
      ORDER BY violation_date DESC
    EOT
  }
}

# gcloud Commands for Management
output "management_commands" {
  description = "Useful gcloud commands for managing the compliance monitoring system"
  value = {
    # Function management
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.compliance_detector.name} --region=${var.region} --limit=50"
    describe_function  = "gcloud functions describe ${google_cloudfunctions2_function.compliance_detector.name} --region=${var.region}"
    
    # Pub/Sub management
    pull_messages     = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.compliance_alerts.name} --auto-ack --limit=10"
    publish_test_message = "gcloud pubsub topics publish ${google_pubsub_topic.compliance_alerts.name} --message='Test compliance alert'"
    
    # BigQuery management
    query_violations  = "bq query --use_legacy_sql=false 'SELECT * FROM `${local.project_id}.${google_bigquery_dataset.compliance_logs.dataset_id}.violations` ORDER BY timestamp DESC LIMIT 10'"
    describe_dataset  = "bq show ${local.project_id}:${google_bigquery_dataset.compliance_logs.dataset_id}"
    
    # Monitoring
    list_alert_policies = "gcloud alpha monitoring policies list --filter='displayName:\"${google_monitoring_alert_policy.high_severity_violations.display_name}\"'"
    view_metrics       = "gcloud logging metrics list --filter='name:${google_logging_metric.compliance_violations.name}'"
  }
}

# Resource Identifiers for Integration
output "resource_ids" {
  description = "Resource identifiers for integration with other systems"
  value = {
    function_name           = google_cloudfunctions2_function.compliance_detector.name
    function_service_account = google_service_account.function_sa.email
    pubsub_topic           = google_pubsub_topic.compliance_alerts.id
    pubsub_subscription    = google_pubsub_subscription.compliance_alerts.id
    bigquery_dataset       = google_bigquery_dataset.compliance_logs.id
    bigquery_table         = google_bigquery_table.violations.id
    log_sink               = google_logging_project_sink.compliance_audit_sink.id
    storage_bucket         = google_storage_bucket.function_source.id
    alert_policy           = google_monitoring_alert_policy.high_severity_violations.id
    dashboard              = google_monitoring_dashboard.compliance_monitoring.id
  }
}

# Security Information
output "security_information" {
  description = "Security-related information about the deployed compliance system"
  value = {
    function_service_account_email = google_service_account.function_sa.email
    function_ingress_settings     = var.function_ingress_settings
    bigquery_access_controls      = "Dataset has project-level access controls configured"
    pubsub_encryption            = "Messages encrypted at rest and in transit using Google-managed keys"
    audit_log_retention          = "${var.log_retention_days} days"
    vpc_connector_enabled        = var.enable_vpc_connector
  }
}

# Cost Information
output "cost_information" {
  description = "Information about resources that may incur costs"
  value = {
    function_scaling = "Function scales from ${var.function_min_instances} to ${var.function_max_instances} instances"
    bigquery_storage = "BigQuery data retained for ${var.log_retention_days} days with automatic partitioning"
    pubsub_retention = "Pub/Sub messages retained for ${var.message_retention_duration}"
    storage_lifecycle = "Function source code bucket has 30-day lifecycle policy"
    monitoring_costs = "Custom metrics and dashboards may incur additional monitoring charges"
  }
}