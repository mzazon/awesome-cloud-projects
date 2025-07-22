# outputs.tf
# Output Values for Data Privacy Compliance Infrastructure

# ==============================================================================
# PROJECT AND GENERAL INFORMATION
# ==============================================================================

output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where regional resources are deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix added to resource names for uniqueness"
  value       = local.resource_suffix
}

# ==============================================================================
# CLOUD STORAGE OUTPUTS
# ==============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for data scanning"
  value       = google_storage_bucket.dlp_data_bucket.name
}

output "storage_bucket_url" {
  description = "Complete URL of the Cloud Storage bucket"
  value       = google_storage_bucket.dlp_data_bucket.url
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.dlp_data_bucket.location
}

output "audit_logs_bucket_name" {
  description = "Name of the audit logs storage bucket"
  value       = google_storage_bucket.audit_logs_bucket.name
}

output "sample_data_paths" {
  description = "Paths to sample data files for testing DLP scanning"
  value = {
    customer_data   = "gs://${google_storage_bucket.dlp_data_bucket.name}/${google_storage_bucket_object.sample_customer_data.name}"
    privacy_policy  = "gs://${google_storage_bucket.dlp_data_bucket.name}/${google_storage_bucket_object.sample_privacy_policy.name}"
  }
}

# ==============================================================================
# BIGQUERY OUTPUTS
# ==============================================================================

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for privacy compliance analytics"
  value       = google_bigquery_dataset.privacy_compliance.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.privacy_compliance.location
}

output "dlp_scan_results_table" {
  description = "Full table reference for DLP scan results"
  value       = "${var.project_id}.${google_bigquery_dataset.privacy_compliance.dataset_id}.${google_bigquery_table.dlp_scan_results.table_id}"
}

output "compliance_summary_table" {
  description = "Full table reference for compliance summary metrics"
  value       = "${var.project_id}.${google_bigquery_dataset.privacy_compliance.dataset_id}.${google_bigquery_table.compliance_summary.table_id}"
}

output "bigquery_console_url" {
  description = "URL to access BigQuery console for the compliance dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.privacy_compliance.dataset_id}"
}

# ==============================================================================
# CLOUD DLP OUTPUTS
# ==============================================================================

output "dlp_inspect_template_name" {
  description = "Name of the Cloud DLP inspect template"
  value       = google_data_loss_prevention_inspect_template.privacy_compliance.name
}

output "dlp_info_types" {
  description = "List of information types configured for DLP scanning"
  value       = var.dlp_info_types
}

output "dlp_min_likelihood" {
  description = "Minimum likelihood threshold for DLP findings"
  value       = var.dlp_min_likelihood
}

# ==============================================================================
# PUB/SUB OUTPUTS
# ==============================================================================

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for DLP notifications"
  value       = google_pubsub_topic.dlp_notifications.name
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for the Cloud Function"
  value       = google_pubsub_subscription.dlp_function_subscription.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dlp_dead_letter.name
}

# ==============================================================================
# CLOUD FUNCTION OUTPUTS
# ==============================================================================

output "cloud_function_name" {
  description = "Name of the Cloud Function for DLP remediation"
  value       = google_cloudfunctions_function.dlp_remediation.name
}

output "cloud_function_trigger" {
  description = "Trigger configuration for the Cloud Function"
  value       = google_cloudfunctions_function.dlp_remediation.event_trigger
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "cloud_function_url" {
  description = "URL to view the Cloud Function in the console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.dlp_remediation.name}?project=${var.project_id}"
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

output "monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled for the solution"
  value       = var.enable_monitoring
}

output "log_metric_name" {
  description = "Name of the log-based metric for high-risk PII detections"
  value       = var.enable_monitoring ? google_logging_metric.high_risk_pii_detections[0].name : null
}

output "alert_policy_name" {
  description = "Name of the alert policy for high-risk PII detections"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_alert_policy.high_risk_pii_alert[0].display_name : null
}

output "notification_email" {
  description = "Email address configured for compliance notifications"
  value       = var.notification_email != "" ? var.notification_email : "Not configured"
  sensitive   = true
}

# ==============================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# ==============================================================================

output "uniform_bucket_access_enabled" {
  description = "Whether uniform bucket-level access is enabled"
  value       = google_storage_bucket.dlp_data_bucket.uniform_bucket_level_access
}

output "bucket_public_access_prevention" {
  description = "Public access prevention setting for the storage bucket"
  value       = google_storage_bucket.dlp_data_bucket.public_access_prevention
}

output "audit_logs_enabled" {
  description = "Whether audit logs are enabled for compliance tracking"
  value       = var.enable_audit_logs
}

output "kms_encryption_enabled" {
  description = "Whether KMS encryption is configured"
  value       = var.kms_key_name != ""
}

# ==============================================================================
# COST MANAGEMENT OUTPUTS
# ==============================================================================

output "budget_enabled" {
  description = "Whether budget monitoring is enabled"
  value       = var.enable_cost_controls
}

output "budget_amount" {
  description = "Configured budget amount in USD"
  value       = var.budget_amount
}

output "cost_monitoring_url" {
  description = "URL to view cost monitoring in the console"
  value       = "https://console.cloud.google.com/billing/budgets?project=${var.project_id}"
}

# ==============================================================================
# DEPLOYMENT VERIFICATION OUTPUTS
# ==============================================================================

output "deployment_commands" {
  description = "Commands to verify the deployment and test DLP scanning"
  value = {
    list_bucket_contents = "gsutil ls -r gs://${google_storage_bucket.dlp_data_bucket.name}/"
    query_scan_results   = "bq query --use_legacy_sql=false 'SELECT COUNT(*) as total_findings FROM `${var.project_id}.${google_bigquery_dataset.privacy_compliance.dataset_id}.${google_bigquery_table.dlp_scan_results.table_id}`'"
    view_function_logs   = "gcloud functions logs read ${google_cloudfunctions_function.dlp_remediation.name} --region ${var.region} --limit 10"
    test_dlp_scan       = "gcloud dlp inspect-content --project ${var.project_id} --content 'My SSN is 123-45-6789 and email is test@example.com'"
  }
}

output "compliance_dashboard_sql" {
  description = "SQL query to create a compliance dashboard view"
  value = <<-EOT
    SELECT 
      DATE(scan_timestamp) as scan_date,
      info_type,
      likelihood,
      COUNT(*) as finding_count,
      compliance_status,
      ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(PARTITION BY DATE(scan_timestamp)), 2) as percentage_of_daily_findings
    FROM `${var.project_id}.${google_bigquery_dataset.privacy_compliance.dataset_id}.${google_bigquery_table.dlp_scan_results.table_id}`
    WHERE scan_timestamp >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    GROUP BY scan_date, info_type, likelihood, compliance_status
    ORDER BY scan_date DESC, finding_count DESC
  EOT
}

# ==============================================================================
# NEXT STEPS GUIDANCE
# ==============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = <<-EOT
    1. Upload test data to gs://${google_storage_bucket.dlp_data_bucket.name}/data/
    2. Run DLP scan: gcloud dlp jobs create storage --storage-config-url=gs://${google_storage_bucket.dlp_data_bucket.name}/* --project=${var.project_id}
    3. Monitor results in BigQuery: ${var.project_id}.${google_bigquery_dataset.privacy_compliance.dataset_id}
    4. Check Cloud Function logs: gcloud functions logs read ${google_cloudfunctions_function.dlp_remediation.name}
    5. Set up compliance reporting dashboards in Data Studio
    6. Configure additional DLP templates for specific compliance requirements
    7. Implement custom remediation logic in the Cloud Function
    8. Review and adjust DLP sensitivity thresholds based on findings
  EOT
}

output "important_notes" {
  description = "Important security and compliance notes"
  value = <<-EOT
    SECURITY NOTES:
    - Sample data contains PII for testing purposes only
    - Remove sample data before production use
    - Review IAM permissions and adjust for your organization
    - Enable VPC Service Controls for additional security
    - Configure customer-managed encryption keys (CMEK) for sensitive data
    
    COMPLIANCE NOTES:
    - Configure data retention policies according to regulations
    - Set up regular compliance reporting workflows
    - Document data processing activities for GDPR Article 30
    - Implement data subject access request (DSAR) procedures
    - Regular review and update of DLP detection rules required
    
    COST OPTIMIZATION:
    - Monitor DLP API usage and costs
    - Implement data lifecycle policies
    - Use appropriate BigQuery slot reservations for predictable costs
    - Consider Cloud Storage class transitions for long-term data
  EOT
}

# ==============================================================================
# EXTERNAL INTEGRATION OUTPUTS
# ==============================================================================

output "api_endpoints" {
  description = "API endpoints for external integration"
  value = {
    dlp_api           = "https://dlp.googleapis.com/v2/projects/${var.project_id}"
    bigquery_api      = "https://bigquery.googleapis.com/bigquery/v2/projects/${var.project_id}/datasets/${google_bigquery_dataset.privacy_compliance.dataset_id}"
    storage_api       = "https://storage.googleapis.com/storage/v1/b/${google_storage_bucket.dlp_data_bucket.name}"
    cloud_function_api = "https://cloudfunctions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/functions/${google_cloudfunctions_function.dlp_remediation.name}"
  }
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}