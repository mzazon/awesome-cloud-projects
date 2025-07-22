# Outputs for Document Intelligence Workflows with Agentspace and Sensitive Data Protection
# This file defines outputs that provide important information after deployment

# Project and Region Information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}

# Document AI Processor Information
output "document_processor_id" {
  description = "ID of the Document AI processor for document analysis"
  value       = google_document_ai_processor.enterprise_processor.name
}

output "document_processor_display_name" {
  description = "Display name of the Document AI processor"
  value       = google_document_ai_processor.enterprise_processor.display_name
}

output "document_processor_type" {
  description = "Type of the Document AI processor"
  value       = google_document_ai_processor.enterprise_processor.type
}

# Cloud Storage Bucket Information
output "input_bucket_name" {
  description = "Name of the Cloud Storage bucket for document input"
  value       = google_storage_bucket.input_bucket.name
}

output "input_bucket_url" {
  description = "URL of the Cloud Storage bucket for document input"
  value       = google_storage_bucket.input_bucket.url
}

output "output_bucket_name" {
  description = "Name of the Cloud Storage bucket for processed document output"
  value       = google_storage_bucket.output_bucket.name
}

output "output_bucket_url" {
  description = "URL of the Cloud Storage bucket for processed document output"
  value       = google_storage_bucket.output_bucket.url
}

output "audit_bucket_name" {
  description = "Name of the Cloud Storage bucket for audit logs and compliance tracking"
  value       = google_storage_bucket.audit_bucket.name
}

output "audit_bucket_url" {
  description = "URL of the Cloud Storage bucket for audit logs and compliance tracking"
  value       = google_storage_bucket.audit_bucket.url
}

# DLP Template Information
output "dlp_inspect_template_id" {
  description = "ID of the DLP inspection template for PII detection"
  value       = google_data_loss_prevention_inspect_template.pii_scanner.name
}

output "dlp_inspect_template_display_name" {
  description = "Display name of the DLP inspection template"
  value       = google_data_loss_prevention_inspect_template.pii_scanner.display_name
}

output "dlp_deidentify_template_id" {
  description = "ID of the DLP de-identification template for data redaction"
  value       = google_data_loss_prevention_deidentify_template.data_redaction.name
}

output "dlp_deidentify_template_display_name" {
  description = "Display name of the DLP de-identification template"
  value       = google_data_loss_prevention_deidentify_template.data_redaction.display_name
}

# Cloud Workflows Information
output "workflow_name" {
  description = "Name of the Cloud Workflow for document processing orchestration"
  value       = google_workflows_workflow.document_processing.name
}

output "workflow_region" {
  description = "Region where the Cloud Workflow is deployed"
  value       = google_workflows_workflow.document_processing.region
}

output "workflow_service_account" {
  description = "Service account used by the Cloud Workflow"
  value       = google_workflows_workflow.document_processing.service_account
}

# BigQuery Information
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for document intelligence analytics"
  value       = google_bigquery_dataset.document_intelligence.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.document_intelligence.location
}

output "bigquery_table_id" {
  description = "ID of the BigQuery table for processed document metadata"
  value       = google_bigquery_table.processed_documents.table_id
}

output "bigquery_compliance_view_id" {
  description = "ID of the BigQuery view for compliance reporting"
  value       = google_bigquery_table.compliance_summary.table_id
}

output "bigquery_table_full_name" {
  description = "Full name of the BigQuery table in project.dataset.table format"
  value       = "${var.project_id}.${google_bigquery_dataset.document_intelligence.dataset_id}.${google_bigquery_table.processed_documents.table_id}"
}

# Service Account Information
output "agentspace_service_account_email" {
  description = "Email address of the Agentspace service account"
  value       = google_service_account.agentspace_processor.email
}

output "agentspace_service_account_id" {
  description = "ID of the Agentspace service account"
  value       = google_service_account.agentspace_processor.account_id
}

output "agentspace_service_account_unique_id" {
  description = "Unique ID of the Agentspace service account"
  value       = google_service_account.agentspace_processor.unique_id
}

# Monitoring and Logging Information
output "audit_log_sink_name" {
  description = "Name of the audit log sink for compliance tracking"
  value       = google_logging_project_sink.audit_sink.name
}

output "audit_log_sink_destination" {
  description = "Destination of the audit log sink"
  value       = google_logging_project_sink.audit_sink.destination
}

output "document_processing_metric_name" {
  description = "Name of the custom metric for document processing volume"
  value       = google_logging_metric.document_processing_volume.name
}

output "sensitive_data_metric_name" {
  description = "Name of the custom metric for sensitive data detections"
  value       = google_logging_metric.sensitive_data_detections.name
}

# Alert Policy Information (conditional output based on variable)
output "monitoring_alert_policy_name" {
  description = "Name of the monitoring alert policy for high-risk processing (if enabled)"
  value       = var.enable_monitoring_alerts ? google_monitoring_alert_policy.high_risk_processing[0].display_name : "Monitoring alerts disabled"
}

# Deployment Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed document intelligence infrastructure"
  value = {
    project_id                    = var.project_id
    region                       = var.region
    environment                  = var.environment
    document_processor_name      = google_document_ai_processor.enterprise_processor.name
    input_bucket                 = google_storage_bucket.input_bucket.name
    output_bucket               = google_storage_bucket.output_bucket.name
    audit_bucket                = google_storage_bucket.audit_bucket.name
    workflow_name               = google_workflows_workflow.document_processing.name
    bigquery_dataset            = google_bigquery_dataset.document_intelligence.dataset_id
    service_account_email       = google_service_account.agentspace_processor.email
    dlp_inspect_template        = google_data_loss_prevention_inspect_template.pii_scanner.name
    dlp_deidentify_template     = google_data_loss_prevention_deidentify_template.data_redaction.name
    monitoring_alerts_enabled   = var.enable_monitoring_alerts
  }
}

# Resource URLs for Quick Access
output "resource_urls" {
  description = "Quick access URLs for key resources in the Google Cloud Console"
  value = {
    document_ai_console     = "https://console.cloud.google.com/ai/document-ai/processors?project=${var.project_id}"
    dlp_console            = "https://console.cloud.google.com/security/dlp?project=${var.project_id}"
    workflows_console      = "https://console.cloud.google.com/workflows?project=${var.project_id}"
    storage_console        = "https://console.cloud.google.com/storage?project=${var.project_id}"
    bigquery_console       = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    monitoring_console     = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    logging_console        = "https://console.cloud.google.com/logs?project=${var.project_id}"
  }
}

# CLI Commands for Common Operations
output "useful_commands" {
  description = "Useful CLI commands for interacting with the deployed infrastructure"
  value = {
    # Document processing workflow execution
    execute_workflow = "gcloud workflows run ${google_workflows_workflow.document_processing.name} --data='{\"document_path\": \"sample.pdf\", \"document_content\": \"<base64-encoded-content>\"}' --location=${var.region}"
    
    # Storage operations
    upload_document = "gsutil cp /path/to/document.pdf gs://${google_storage_bucket.input_bucket.name}/"
    list_processed  = "gsutil ls gs://${google_storage_bucket.output_bucket.name}/"
    
    # BigQuery operations
    query_processed_docs = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.document_intelligence.dataset_id}.${google_bigquery_table.processed_documents.table_id}` LIMIT 10'"
    compliance_summary   = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.document_intelligence.dataset_id}.${google_bigquery_table.compliance_summary.table_id}`'"
    
    # Monitoring operations
    view_logs = "gcloud logging read \"protoPayload.serviceName=\\\"documentai.googleapis.com\\\"\" --limit=10 --project=${var.project_id}"
    check_metrics = "gcloud logging metrics list --filter=\"name:document_processing\" --project=${var.project_id}"
  }
}

# Security and Compliance Information
output "security_configuration" {
  description = "Security and compliance configuration summary"
  value = {
    uniform_bucket_access        = var.enable_uniform_bucket_level_access
    public_access_prevention     = var.enable_bucket_public_access_prevention
    bucket_versioning_enabled    = var.bucket_versioning_enabled
    dlp_min_likelihood          = var.dlp_min_likelihood
    dlp_info_types_count        = length(var.dlp_info_types)
    audit_log_retention_days    = var.log_retention_days
    monitoring_alerts_enabled   = var.enable_monitoring_alerts
    service_account_permissions = [
      "roles/documentai.apiUser",
      "roles/dlp.user", 
      "roles/workflows.invoker",
      "roles/storage.admin",
      "roles/bigquery.dataEditor"
    ]
  }
}

# Cost and Resource Information
output "cost_optimization_info" {
  description = "Information for cost optimization and resource management"
  value = {
    storage_class               = var.storage_class
    bucket_lifecycle_days       = var.bucket_lifecycle_age_days
    bigquery_location          = var.bigquery_dataset_location
    bigquery_table_expiration  = var.bigquery_table_expiration_days > 0 ? "${var.bigquery_table_expiration_days} days" : "No expiration"
    workflow_timeout           = "${var.workflow_timeout} seconds"
    estimated_monthly_cost_usd = "Varies based on document volume and processing frequency. Monitor using Cloud Billing console."
  }
}