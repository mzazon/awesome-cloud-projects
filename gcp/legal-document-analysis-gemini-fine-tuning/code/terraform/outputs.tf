# Outputs for Legal Document Analysis with Gemini Fine-Tuning Infrastructure
# This file defines the outputs that will be displayed after deployment

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "resource_prefix" {
  description = "The prefix used for resource naming"
  value       = local.name_prefix
}

# Storage bucket outputs
output "legal_documents_bucket" {
  description = "Cloud Storage bucket for uploading legal documents to be processed"
  value       = google_storage_bucket.legal_documents.name
}

output "legal_documents_bucket_url" {
  description = "Google Cloud Console URL for the legal documents bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.legal_documents.name}"
}

output "training_data_bucket" {
  description = "Cloud Storage bucket containing training data for model fine-tuning"
  value       = google_storage_bucket.training_data.name
}

output "analysis_results_bucket" {
  description = "Cloud Storage bucket where analysis results and dashboard are stored"
  value       = google_storage_bucket.analysis_results.name
}

output "analysis_results_bucket_url" {
  description = "Google Cloud Console URL for the analysis results bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.analysis_results.name}"
}

# Document AI outputs
output "document_ai_processor_id" {
  description = "The ID of the Document AI processor for legal document processing"
  value       = google_document_ai_processor.legal_processor.name
}

output "document_ai_processor_display_name" {
  description = "The display name of the Document AI processor"
  value       = google_document_ai_processor.legal_processor.display_name
}

output "document_ai_processor_type" {
  description = "The type of Document AI processor created"
  value       = google_document_ai_processor.legal_processor.type
}

# Cloud Functions outputs
output "document_processor_function_name" {
  description = "Name of the Cloud Function that processes legal documents"
  value       = google_cloudfunctions2_function.document_processor.name
}

output "document_processor_function_url" {
  description = "Google Cloud Console URL for the document processor function"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.document_processor.name}"
}

output "dashboard_generator_function_name" {
  description = "Name of the Cloud Function that generates the legal analysis dashboard"
  value       = google_cloudfunctions2_function.dashboard_generator.name
}

output "dashboard_generator_function_url" {
  description = "HTTP trigger URL for the dashboard generator function"
  value       = google_cloudfunctions2_function.dashboard_generator.service_config[0].uri
}

output "dashboard_generator_console_url" {
  description = "Google Cloud Console URL for the dashboard generator function"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.dashboard_generator.name}"
}

# Service account outputs
output "function_service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "function_service_account_id" {
  description = "The unique ID of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.unique_id
}

# Monitoring outputs (conditional)
output "monitoring_enabled" {
  description = "Whether Cloud Monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "notification_email" {
  description = "Email address configured for monitoring notifications (if any)"
  value       = var.notification_email != "" ? var.notification_email : "Not configured"
  sensitive   = var.notification_email != ""
}

output "alert_policy_id" {
  description = "ID of the monitoring alert policy (if monitoring is enabled)"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_alert_policy.function_error_alert[0].name : "Not created"
}

# Security and access outputs
output "public_access_enabled" {
  description = "Whether public access to the dashboard function is enabled"
  value       = var.enable_public_access
}

output "storage_versioning_enabled" {
  description = "Whether versioning is enabled on storage buckets"
  value       = var.enable_versioning
}

output "retention_days" {
  description = "Number of days documents and results are retained"
  value       = var.retention_days
}

# Training configuration outputs
output "gemini_base_model" {
  description = "Base Gemini model configured for fine-tuning"
  value       = var.gemini_model_base
}

output "tuning_epochs" {
  description = "Number of epochs configured for model fine-tuning"
  value       = var.tuning_epochs
}

output "learning_rate_multiplier" {
  description = "Learning rate multiplier configured for fine-tuning"
  value       = var.learning_rate_multiplier
}

# Usage instructions
output "usage_instructions" {
  description = "Instructions for using the deployed legal document analysis system"
  value = <<EOF
Legal Document Analysis System Deployed Successfully!

📋 USAGE INSTRUCTIONS:

1. Upload Documents:
   - Upload legal documents (PDF format recommended) to: gs://${google_storage_bucket.legal_documents.name}
   - Documents will be automatically processed by the Cloud Function

2. View Results:
   - Analysis results are stored in: gs://${google_storage_bucket.analysis_results.name}
   - Each document gets an analysis_{filename}.json result file

3. Generate Dashboard:
   - Call the dashboard function: ${google_cloudfunctions2_function.dashboard_generator.service_config[0].uri}
   - View dashboard: gs://${google_storage_bucket.analysis_results.name}/legal_dashboard.html

4. Monitor Processing:
   - Function logs: gcloud functions logs read ${google_cloudfunctions2_function.document_processor.name} --gen2 --region=${var.region}
   - Storage console: https://console.cloud.google.com/storage/browser/${google_storage_bucket.legal_documents.name}

5. Fine-Tune Model (Advanced):
   - Training data location: gs://${google_storage_bucket.training_data.name}/legal_training_examples.jsonl
   - Modify training data and retrain model using Vertex AI console

🔒 SECURITY NOTES:
   - All buckets have uniform bucket-level access control enabled
   - Public access prevention is enforced on all storage buckets
   - Functions run with least-privilege service account permissions
   - ${var.enable_public_access ? "⚠️  Public access to dashboard is ENABLED" : "✅ Dashboard access is restricted to authenticated users"}

📊 MONITORING:
   - ${var.enable_monitoring ? "✅ Cloud Monitoring is enabled" : "❌ Cloud Monitoring is disabled"}
   - ${var.notification_email != "" ? "✅ Email notifications configured" : "❌ No email notifications configured"}

💰 COST OPTIMIZATION:
   - Document retention: ${var.retention_days} days
   - Function memory: ${var.function_memory}MB
   - Storage versioning: ${var.enable_versioning ? "enabled" : "disabled"}

EOF
}

# Quick start commands
output "quick_start_commands" {
  description = "Quick start commands for testing the system"
  value = <<EOF
# Test the system with these commands:

# 1. Upload a sample document
echo "Sample legal contract text..." > sample_contract.txt
gsutil cp sample_contract.txt gs://${google_storage_bucket.legal_documents.name}/

# 2. Check processing logs
gcloud functions logs read ${google_cloudfunctions2_function.document_processor.name} --gen2 --region=${var.region} --limit=10

# 3. Generate dashboard
curl -X GET "${google_cloudfunctions2_function.dashboard_generator.service_config[0].uri}"

# 4. View analysis results
gsutil ls gs://${google_storage_bucket.analysis_results.name}/

# 5. Download dashboard
gsutil cp gs://${google_storage_bucket.analysis_results.name}/legal_dashboard.html ./

EOF
}