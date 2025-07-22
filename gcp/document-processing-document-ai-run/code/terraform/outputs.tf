# Output Values for Document Processing Infrastructure
# These outputs provide important information about the deployed resources

# Project and Region Information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

# Document AI Processor Information
output "document_ai_processor_id" {
  description = "The ID of the Document AI processor"
  value       = google_document_ai_processor.form_processor.id
}

output "document_ai_processor_name" {
  description = "The full resource name of the Document AI processor"
  value       = google_document_ai_processor.form_processor.name
}

output "document_ai_processor_display_name" {
  description = "The display name of the Document AI processor"
  value       = google_document_ai_processor.form_processor.display_name
}

output "document_ai_processor_type" {
  description = "The type of Document AI processor created"
  value       = google_document_ai_processor.form_processor.type
}

# Cloud Storage Information
output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket for document uploads"
  value       = google_storage_bucket.document_uploads.name
}

output "storage_bucket_url" {
  description = "The URL of the Cloud Storage bucket"
  value       = google_storage_bucket.document_uploads.url
}

output "storage_bucket_self_link" {
  description = "The self link of the Cloud Storage bucket"
  value       = google_storage_bucket.document_uploads.self_link
}

# Pub/Sub Information
output "pubsub_topic_name" {
  description = "The name of the Pub/Sub topic for document processing"
  value       = google_pubsub_topic.document_processing.name
}

output "pubsub_topic_id" {
  description = "The full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.document_processing.id
}

output "pubsub_subscription_name" {
  description = "The name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.document_worker.name
}

output "pubsub_subscription_id" {
  description = "The full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.document_worker.id
}

output "pubsub_dead_letter_topic_name" {
  description = "The name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter.name
}

# Cloud Run Service Information
output "cloud_run_service_name" {
  description = "The name of the Cloud Run service"
  value       = google_cloud_run_v2_service.document_processor.name
}

output "cloud_run_service_url" {
  description = "The URL of the Cloud Run service"
  value       = google_cloud_run_v2_service.document_processor.uri
}

output "cloud_run_service_location" {
  description = "The location of the Cloud Run service"
  value       = google_cloud_run_v2_service.document_processor.location
}

output "cloud_run_service_id" {
  description = "The full resource ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.document_processor.id
}

output "cloud_run_latest_ready_revision" {
  description = "The name of the latest ready revision"
  value       = google_cloud_run_v2_service.document_processor.latest_ready_revision
}

# Service Account Information
output "service_account_email" {
  description = "The email address of the service account used by Cloud Run"
  value       = google_service_account.cloud_run_sa.email
}

output "service_account_name" {
  description = "The name of the service account"
  value       = google_service_account.cloud_run_sa.name
}

output "service_account_unique_id" {
  description = "The unique ID of the service account"
  value       = google_service_account.cloud_run_sa.unique_id
}

# Resource Names for Reference
output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.resource_suffix
}

output "resource_prefix" {
  description = "The prefix used for resource naming"
  value       = var.resource_prefix
}

# API Endpoints and Configuration
output "document_upload_instructions" {
  description = "Instructions for uploading documents to trigger processing"
  value = <<-EOT
    To upload documents for processing:
    
    1. Using gsutil:
       gsutil cp your-document.pdf gs://${google_storage_bucket.document_uploads.name}/
    
    2. Using Google Cloud Console:
       Navigate to Cloud Storage and upload files to bucket: ${google_storage_bucket.document_uploads.name}
    
    3. Using gcloud:
       gcloud storage cp your-document.pdf gs://${google_storage_bucket.document_uploads.name}/
    
    Processed results will be stored in: gs://${google_storage_bucket.document_uploads.name}/processed/
  EOT
}

# Monitoring and Logging Information
output "monitoring_dashboard_url" {
  description = "URL to view Cloud Run service in Cloud Monitoring"
  value       = "https://console.cloud.google.com/monitoring/dashboards/resourceList/cloud_run_revision?project=${var.project_id}"
}

output "cloud_run_logs_url" {
  description = "URL to view Cloud Run service logs"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_run_revision%22%0Aresource.labels.service_name%3D%22${google_cloud_run_v2_service.document_processor.name}%22?project=${var.project_id}"
}

output "pubsub_monitoring_url" {
  description = "URL to monitor Pub/Sub topic metrics"
  value       = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.document_processing.name}?project=${var.project_id}"
}

# Cost Information
output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs for this infrastructure"
  value = <<-EOT
    Estimated monthly costs (USD) for moderate usage:
    
    - Document AI Form Parser: ~$1.50 per 1,000 pages processed
    - Cloud Run: ~$0.40 per million requests + compute costs
    - Cloud Storage: ~$0.020 per GB stored per month
    - Pub/Sub: ~$0.40 per million messages
    - Network egress: Variable based on data transfer
    
    Total estimated cost for 1,000 documents/month: $5-15 USD
    
    Note: Actual costs depend on document volume, size, and processing complexity.
    Monitor usage in the Cloud Billing console for accurate cost tracking.
  EOT
}

# Security Information
output "security_notes" {
  description = "Important security considerations for this deployment"
  value = <<-EOT
    Security Considerations:
    
    1. Service Account: Uses least-privilege permissions for Document AI, Storage, and Logging
    2. Cloud Run: Configured with HTTPS endpoints and IAM-based access control
    3. Storage: Uniform bucket-level access enabled for consistent permissions
    4. Monitoring: Alert policies configured for error detection
    5. Network: Cloud Run allows all traffic by default - consider restricting ingress if needed
    
    Recommendations:
    - Enable Cloud Audit Logs for compliance tracking
    - Consider enabling Binary Authorization for container security
    - Implement Cloud KMS encryption for sensitive documents
    - Review IAM permissions regularly
  EOT
}

# Testing Information
output "testing_commands" {
  description = "Commands to test the document processing pipeline"
  value = <<-EOT
    Test the document processing pipeline:
    
    1. Create a test document:
       echo "Test Document Content" > test-document.txt
    
    2. Upload to trigger processing:
       gsutil cp test-document.txt gs://${google_storage_bucket.document_uploads.name}/
    
    3. Check processing logs:
       gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=${google_cloud_run_v2_service.document_processor.name}" --limit=10
    
    4. View processed results:
       gsutil ls gs://${google_storage_bucket.document_uploads.name}/processed/
    
    5. Monitor Pub/Sub metrics:
       gcloud pubsub topics describe ${google_pubsub_topic.document_processing.name}
  EOT
}

# Version Information
output "terraform_version_info" {
  description = "Terraform and provider version information"
  value = {
    terraform_version = ">=1.0"
    google_provider_version = "~>6.0"
    deployment_timestamp = timestamp()
  }
}