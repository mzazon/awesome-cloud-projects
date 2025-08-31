# Outputs for the automated regulatory compliance system
# These outputs provide essential information for system operation and integration

# Project and region information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource uniqueness"
  value       = random_id.suffix.hex
}

# Cloud Storage bucket information
output "input_bucket_name" {
  description = "Name of the Cloud Storage bucket for input documents"
  value       = google_storage_bucket.input_bucket.name
}

output "input_bucket_url" {
  description = "URL of the input bucket for document uploads"
  value       = google_storage_bucket.input_bucket.url
}

output "processed_bucket_name" {
  description = "Name of the Cloud Storage bucket for processed documents"
  value       = google_storage_bucket.processed_bucket.name
}

output "processed_bucket_url" {
  description = "URL of the processed documents bucket"
  value       = google_storage_bucket.processed_bucket.url
}

output "reports_bucket_name" {
  description = "Name of the Cloud Storage bucket for compliance reports"
  value       = google_storage_bucket.reports_bucket.name
}

output "reports_bucket_url" {
  description = "URL of the compliance reports bucket"
  value       = google_storage_bucket.reports_bucket.url
}

# Document AI processor information
output "document_ai_processor_id" {
  description = "ID of the Document AI processor"
  value       = google_document_ai_processor.compliance_processor.name
}

output "document_ai_processor_display_name" {
  description = "Display name of the Document AI processor"
  value       = google_document_ai_processor.compliance_processor.display_name
}

output "document_ai_location" {
  description = "Location of the Document AI processor"
  value       = google_document_ai_processor.compliance_processor.location
}

# Cloud Functions information
output "document_processor_function_name" {
  description = "Name of the document processing Cloud Function"
  value       = google_cloudfunctions2_function.document_processor.name
}

output "document_processor_function_url" {
  description = "URL of the document processing Cloud Function"
  value       = google_cloudfunctions2_function.document_processor.service_config[0].uri
}

output "report_generator_function_name" {
  description = "Name of the report generation Cloud Function"
  value       = google_cloudfunctions2_function.report_generator.name
}

output "report_generator_function_url" {
  description = "URL of the report generation Cloud Function"
  value       = google_cloudfunctions2_function.report_generator.service_config[0].uri
}

# Service account information
output "function_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "function_service_account_id" {
  description = "ID of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.account_id
}

# Cloud Scheduler job information
output "daily_scheduler_job_name" {
  description = "Name of the daily compliance report scheduler job"
  value       = google_cloud_scheduler_job.daily_compliance_report.name
}

output "weekly_scheduler_job_name" {
  description = "Name of the weekly compliance report scheduler job"
  value       = google_cloud_scheduler_job.weekly_compliance_report.name
}

output "monthly_scheduler_job_name" {
  description = "Name of the monthly compliance report scheduler job"
  value       = google_cloud_scheduler_job.monthly_compliance_report.name
}

output "scheduler_jobs_region" {
  description = "Region where Cloud Scheduler jobs are deployed"
  value       = var.region
}

# Monitoring and alerting information
output "compliance_violations_metric_name" {
  description = "Name of the compliance violations log metric"
  value       = google_logging_metric.compliance_violations.name
}

output "processing_errors_metric_name" {
  description = "Name of the processing errors log metric"
  value       = google_logging_metric.processing_errors.name
}

output "successful_processing_metric_name" {
  description = "Name of the successful processing log metric"
  value       = google_logging_metric.successful_processing.name
}

output "notification_channel_id" {
  description = "ID of the email notification channel for alerts"
  value       = google_monitoring_notification_channel.compliance_email.id
}

output "compliance_violations_alert_policy_name" {
  description = "Name of the compliance violations alert policy"
  value       = google_monitoring_alert_policy.compliance_violations_alert.display_name
}

output "processing_errors_alert_policy_name" {
  description = "Name of the processing errors alert policy"
  value       = google_monitoring_alert_policy.processing_errors_alert.display_name
}

# Eventarc trigger information
output "document_trigger_name" {
  description = "Name of the Eventarc trigger for document processing"
  value       = google_eventarc_trigger.document_trigger.name
}

output "document_trigger_location" {
  description = "Location of the Eventarc trigger"
  value       = google_eventarc_trigger.document_trigger.location
}

# Usage instructions
output "upload_instructions" {
  description = "Instructions for uploading documents to trigger processing"
  value = <<-EOT
    To upload documents for processing, use one of these methods:
    
    1. Using gsutil CLI:
       gsutil cp your-document.pdf gs://${google_storage_bucket.input_bucket.name}/
    
    2. Using Google Cloud Console:
       Navigate to Cloud Storage > ${google_storage_bucket.input_bucket.name} > Upload files
    
    3. Using the API or client libraries:
       Upload to bucket: ${google_storage_bucket.input_bucket.name}
  EOT
}

output "manual_report_generation" {
  description = "Instructions for manually triggering report generation"
  value = <<-EOT
    To manually generate compliance reports, use curl or HTTP client:
    
    Daily report:
    curl -X POST -H "Content-Type: application/json" \
         -d '{"report_type": "daily"}' \
         "${google_cloudfunctions2_function.report_generator.service_config[0].uri}"
    
    Weekly report:
    curl -X POST -H "Content-Type: application/json" \
         -d '{"report_type": "weekly"}' \
         "${google_cloudfunctions2_function.report_generator.service_config[0].uri}"
    
    Monthly report:
    curl -X POST -H "Content-Type: application/json" \
         -d '{"report_type": "monthly"}' \
         "${google_cloudfunctions2_function.report_generator.service_config[0].uri}"
  EOT
}

output "monitoring_dashboard_link" {
  description = "Link to create a monitoring dashboard"
  value = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
}

output "logs_explorer_link" {
  description = "Link to view function logs in Cloud Logging"
  value = "https://console.cloud.google.com/logs/query?project=${var.project_id}&query=resource.type%3D%22cloud_function%22"
}

output "document_ai_console_link" {
  description = "Link to Document AI console for processor management"
  value = "https://console.cloud.google.com/ai/document-ai/processors?project=${var.project_id}"
}

output "scheduler_console_link" {
  description = "Link to Cloud Scheduler console for job management"
  value = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of the deployed compliance automation system"
  value = {
    environment           = var.environment
    input_bucket         = google_storage_bucket.input_bucket.name
    processed_bucket     = google_storage_bucket.processed_bucket.name
    reports_bucket       = google_storage_bucket.reports_bucket.name
    document_processor   = google_cloudfunctions2_function.document_processor.name
    report_generator     = google_cloudfunctions2_function.report_generator.name
    document_ai_processor = google_document_ai_processor.compliance_processor.name
    scheduler_jobs = {
      daily   = google_cloud_scheduler_job.daily_compliance_report.name
      weekly  = google_cloud_scheduler_job.weekly_compliance_report.name
      monthly = google_cloud_scheduler_job.monthly_compliance_report.name
    }
    monitoring = {
      notification_email = var.notification_email
      metrics_created   = 3
      alert_policies    = 2
    }
  }
}