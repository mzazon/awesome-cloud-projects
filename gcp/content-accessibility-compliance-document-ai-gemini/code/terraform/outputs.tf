# Project and Regional Information
output "project_id" {
  description = "Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where regional resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Cloud Storage Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for document processing"
  value       = google_storage_bucket.document_bucket.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.document_bucket.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.document_bucket.self_link
}

output "upload_folder_url" {
  description = "Cloud Storage URL for uploading documents to be analyzed"
  value       = "gs://${google_storage_bucket.document_bucket.name}/uploads/"
}

output "reports_folder_url" {
  description = "Cloud Storage URL where accessibility reports are stored"
  value       = "gs://${google_storage_bucket.document_bucket.name}/reports/"
}

output "processed_folder_url" {
  description = "Cloud Storage URL where processed documents are archived"
  value       = "gs://${google_storage_bucket.document_bucket.name}/processed/"
}

# Document AI Outputs
output "document_ai_processor_id" {
  description = "ID of the Document AI processor for OCR and layout analysis"
  value       = google_document_ai_processor.accessibility_processor.name
}

output "document_ai_processor_display_name" {
  description = "Display name of the Document AI processor"
  value       = google_document_ai_processor.accessibility_processor.display_name
}

output "document_ai_processor_type" {
  description = "Type of the Document AI processor"
  value       = google_document_ai_processor.accessibility_processor.type
}

output "document_ai_location" {
  description = "Location of the Document AI processor"
  value       = var.document_ai_location
}

# Cloud Function Outputs
output "cloud_function_name" {
  description = "Name of the Cloud Function for accessibility analysis"
  value       = google_cloudfunctions2_function.accessibility_analyzer.name
}

output "cloud_function_url" {
  description = "URL of the Cloud Function"
  value       = google_cloudfunctions2_function.accessibility_analyzer.service_config[0].uri
}

output "cloud_function_service_account" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "cloud_function_trigger_type" {
  description = "Type of trigger for the Cloud Function"
  value       = google_cloudfunctions2_function.accessibility_analyzer.event_trigger[0].event_type
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the service account created for the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "service_account_id" {
  description = "ID of the service account"
  value       = google_service_account.function_sa.account_id
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.function_sa.unique_id
}

# Vertex AI Configuration Outputs
output "vertex_ai_location" {
  description = "Location configured for Vertex AI resources"
  value       = var.vertex_ai_location
}

output "gemini_model" {
  description = "Gemini model configured for accessibility analysis"
  value       = var.gemini_model
}

# Monitoring Outputs
output "monitoring_alert_policy_name" {
  description = "Name of the monitoring alert policy for function errors"
  value       = google_monitoring_alert_policy.function_error_rate.name
}

output "log_sink_name" {
  description = "Name of the log sink for centralized logging"
  value       = google_logging_project_sink.function_logs.name
}

output "log_sink_writer_identity" {
  description = "Writer identity of the log sink"
  value       = google_logging_project_sink.function_logs.writer_identity
}

# Deployment Information
output "deployment_labels" {
  description = "Labels applied to all resources for organization and cost tracking"
  value       = local.common_labels
}

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value       = var.enable_apis
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed accessibility compliance system"
  value = <<-EOT
    Accessibility Compliance System Deployed Successfully!
    
    To use the system:
    1. Upload PDF documents to: gs://${google_storage_bucket.document_bucket.name}/uploads/
    2. Wait for automatic processing (typically 1-3 minutes)
    3. Download accessibility reports from: gs://${google_storage_bucket.document_bucket.name}/reports/
    4. Processed documents are archived in: gs://${google_storage_bucket.document_bucket.name}/processed/
    
    Upload Command Example:
    gsutil cp your-document.pdf gs://${google_storage_bucket.document_bucket.name}/uploads/
    
    Download Reports Example:
    gsutil cp gs://${google_storage_bucket.document_bucket.name}/reports/your-document.pdf_accessibility_report.pdf ./
    
    View Function Logs:
    gcloud functions logs read ${google_cloudfunctions2_function.accessibility_analyzer.name} --region=${var.region}
    
    Monitor Processing:
    gcloud functions describe ${google_cloudfunctions2_function.accessibility_analyzer.name} --region=${var.region}
  EOT
}

# Cost Estimation Information
output "cost_information" {
  description = "Information about potential costs for running this system"
  value = <<-EOT
    Cost Estimation (per month, approximate):
    
    Cloud Storage:
    - Storage: $0.020/GB for STANDARD class
    - Operations: $0.05/10,000 operations
    
    Document AI:
    - OCR Processing: $1.50/1,000 pages
    
    Cloud Functions:
    - Compute: $0.0000004/GB-second + $0.0000025/GHz-second
    - Invocations: $0.40/million invocations
    
    Vertex AI (Gemini):
    - Input tokens: varies by model (~$0.001-0.01/1k tokens)
    - Output tokens: varies by model (~$0.003-0.03/1k tokens)
    
    Example: Processing 100 documents (10 pages each) ≈ $15-25/month
    
    Note: Actual costs depend on document size, processing frequency, and storage duration.
    Monitor usage at: https://console.cloud.google.com/billing
  EOT
}

# Security Information
output "security_notes" {
  description = "Important security information about the deployment"
  value = <<-EOT
    Security Configuration:
    
    ✅ Uniform bucket-level access enabled
    ✅ Public access prevention enforced
    ✅ Service account with least privilege permissions
    ✅ Vertex AI access restricted to authorized service account
    ✅ Document AI processor isolated to project
    ✅ Cloud Function logs and monitoring enabled
    
    Security Best Practices:
    1. Regularly review IAM permissions
    2. Monitor function execution logs for anomalies
    3. Enable VPC Service Controls for additional network security
    4. Use customer-managed encryption keys (CMEK) for sensitive data
    5. Implement data retention policies for compliance
    
    Access Control:
    - Only the service account can process documents
    - Bucket access is controlled via IAM
    - Function execution is logged and monitored
  EOT
}