# Outputs for Smart Document Review Workflow with ADK and Storage
# These outputs provide important information for verification and integration

# Project Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.resource_suffix
}

# Storage Bucket Outputs
output "input_bucket_name" {
  description = "Name of the Cloud Storage bucket for document inputs"
  value       = google_storage_bucket.input_bucket.name
}

output "input_bucket_url" {
  description = "URL of the input bucket for document uploads"
  value       = google_storage_bucket.input_bucket.url
}

output "results_bucket_name" {
  description = "Name of the Cloud Storage bucket for review results"
  value       = google_storage_bucket.results_bucket.name
}

output "results_bucket_url" {
  description = "URL of the results bucket for review outputs"
  value       = google_storage_bucket.results_bucket.url
}

output "input_bucket_self_link" {
  description = "Self-link of the input bucket for API operations"
  value       = google_storage_bucket.input_bucket.self_link
}

output "results_bucket_self_link" {
  description = "Self-link of the results bucket for API operations"
  value       = google_storage_bucket.results_bucket.self_link
}

# Cloud Function Outputs
output "function_name" {
  description = "Name of the document processor Cloud Function"
  value       = google_cloudfunctions2_function.document_processor.name
}

output "function_url" {
  description = "URL of the Cloud Function (if HTTP trigger enabled)"
  value       = google_cloudfunctions2_function.document_processor.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email address of the function service account"
  value       = google_service_account.function_sa.email
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.document_processor.location
}

# Service Account Information
output "function_service_account_id" {
  description = "ID of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.account_id
}

output "function_service_account_unique_id" {
  description = "Unique ID of the function service account"
  value       = google_service_account.function_sa.unique_id
}

# Pub/Sub Information
output "notifications_topic" {
  description = "Name of the Pub/Sub topic for notifications"
  value       = google_pubsub_topic.notifications.name
}

output "notifications_topic_id" {
  description = "Full resource ID of the notifications topic"
  value       = google_pubsub_topic.notifications.id
}

# Monitoring Information
output "monitoring_alert_policy_id" {
  description = "ID of the monitoring alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_error_rate[0].name : null
}

output "log_sink_name" {
  description = "Name of the logging sink for function logs"
  value       = google_logging_project_sink.function_logs.name
}

output "log_sink_writer_identity" {
  description = "Writer identity for the logging sink"
  value       = google_logging_project_sink.function_logs.writer_identity
}

# Budget Information
output "budget_name" {
  description = "Name of the billing budget (if enabled)"
  value       = var.enable_budget_alerts ? google_billing_budget.project_budget[0].display_name : null
}

# API Information
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
}

# Upload Instructions
output "upload_instructions" {
  description = "Instructions for uploading documents to trigger processing"
  value = <<-EOT
    To upload documents for processing:
    
    1. Using gsutil CLI:
       gsutil cp your-document.txt gs://${google_storage_bucket.input_bucket.name}/
    
    2. Using Google Cloud Console:
       - Navigate to Cloud Storage
       - Open bucket: ${google_storage_bucket.input_bucket.name}
       - Click "Upload files" and select your document
    
    3. Supported file types: .txt, .md, .doc, .docx
    
    Results will be available in: gs://${google_storage_bucket.results_bucket.name}/
  EOT
}

# Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = <<-EOT
    Verify deployment with these commands:
    
    1. Check function status:
       gcloud functions describe ${google_cloudfunctions2_function.document_processor.name} --region=${var.region}
    
    2. List buckets:
       gsutil ls -p ${var.project_id}
    
    3. Test upload:
       echo "Test document content" > test.txt
       gsutil cp test.txt gs://${google_storage_bucket.input_bucket.name}/
    
    4. Check results:
       gsutil ls gs://${google_storage_bucket.results_bucket.name}/
    
    5. View function logs:
       gcloud functions logs read ${google_cloudfunctions2_function.document_processor.name} --region=${var.region}
  EOT
}

# Security Information
output "security_summary" {
  description = "Summary of security configurations applied"
  value = <<-EOT
    Security configurations:
    - Uniform bucket-level access: ${var.enable_uniform_bucket_level_access}
    - Bucket versioning: ${var.enable_versioning}
    - Service account with minimal permissions
    - Function timeout: ${var.function_timeout} seconds
    - Max function instances: ${var.function_max_instances}
    - Lifecycle rules configured for automatic cleanup
  EOT
}

# Cost Information
output "cost_monitoring" {
  description = "Cost monitoring and budget information"
  value = <<-EOT
    Cost monitoring:
    - Budget alerts enabled: ${var.enable_budget_alerts}
    - Monthly budget: $${var.budget_amount} USD
    - Storage class: ${var.storage_class}
    - Function memory: ${var.function_memory}
    - Log retention: ${var.log_retention_days} days
    
    To monitor costs:
    - Check billing dashboard in Google Cloud Console
    - Review storage usage: gsutil du -sh gs://${google_storage_bucket.input_bucket.name}/ gs://${google_storage_bucket.results_bucket.name}/
    - Monitor function execution metrics in Cloud Monitoring
  EOT
}

# ADK Configuration
output "adk_configuration" {
  description = "Agent Development Kit configuration details"
  value = <<-EOT
    ADK Configuration:
    - Gemini model: ${var.gemini_model}
    - Vertex AI enabled: ${var.enable_vertex_ai}
    - Multi-agent system with specialized agents:
      * Grammar Agent: Grammar, punctuation, and syntax analysis
      * Accuracy Agent: Fact-checking and content validation
      * Style Agent: Readability and tone consistency analysis
      * Coordinator: Workflow orchestration and result aggregation
    
    Environment variables set for function:
    - PROJECT_ID: ${var.project_id}
    - INPUT_BUCKET: ${google_storage_bucket.input_bucket.name}
    - RESULTS_BUCKET: ${google_storage_bucket.results_bucket.name}
    - GEMINI_MODEL: ${var.gemini_model}
    - ENVIRONMENT: ${var.environment}
  EOT
}

# Cleanup Instructions
output "cleanup_instructions" {
  description = "Instructions for cleaning up resources"
  value = <<-EOT
    To clean up resources:
    
    1. Using Terraform:
       terraform destroy -auto-approve
    
    2. Manual cleanup (if needed):
       # Delete function
       gcloud functions delete ${google_cloudfunctions2_function.document_processor.name} --region=${var.region}
       
       # Delete buckets (this will delete all content)
       gsutil -m rm -r gs://${google_storage_bucket.input_bucket.name}
       gsutil -m rm -r gs://${google_storage_bucket.results_bucket.name}
       
       # Delete service account
       gcloud iam service-accounts delete ${google_service_account.function_sa.email}
       
       # Delete pub/sub topic
       gcloud pubsub topics delete ${google_pubsub_topic.notifications.name}
  EOT
}