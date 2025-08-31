# Output values for the smart content classification infrastructure
# These outputs provide important information about the deployed resources

# Project and regional information
output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

# Storage bucket information
output "staging_bucket_name" {
  description = "Name of the staging bucket for file uploads"
  value       = google_storage_bucket.staging.name
}

output "staging_bucket_url" {
  description = "URL of the staging bucket for file uploads"
  value       = google_storage_bucket.staging.url
}

output "contracts_bucket_name" {
  description = "Name of the contracts classification bucket"
  value       = google_storage_bucket.contracts.name
}

output "contracts_bucket_url" {
  description = "URL of the contracts classification bucket"
  value       = google_storage_bucket.contracts.url
}

output "invoices_bucket_name" {
  description = "Name of the invoices classification bucket"
  value       = google_storage_bucket.invoices.name
}

output "invoices_bucket_url" {
  description = "URL of the invoices classification bucket"
  value       = google_storage_bucket.invoices.url
}

output "marketing_bucket_name" {
  description = "Name of the marketing classification bucket"
  value       = google_storage_bucket.marketing.name
}

output "marketing_bucket_url" {
  description = "URL of the marketing classification bucket"
  value       = google_storage_bucket.marketing.url
}

output "miscellaneous_bucket_name" {
  description = "Name of the miscellaneous classification bucket"
  value       = google_storage_bucket.miscellaneous.name
}

output "miscellaneous_bucket_url" {
  description = "URL of the miscellaneous classification bucket"
  value       = google_storage_bucket.miscellaneous.url
}

# Cloud Function information
output "function_name" {
  description = "Name of the content classification Cloud Function"
  value       = google_cloudfunctions2_function.content_classifier.name
}

output "function_url" {
  description = "URL of the content classification Cloud Function"
  value       = google_cloudfunctions2_function.content_classifier.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.content_classifier.email
}

# Service account information
output "service_account_id" {
  description = "ID of the content classifier service account"
  value       = google_service_account.content_classifier.account_id
}

output "service_account_email" {
  description = "Email address of the content classifier service account"
  value       = google_service_account.content_classifier.email
}

output "service_account_unique_id" {
  description = "Unique ID of the content classifier service account"
  value       = google_service_account.content_classifier.unique_id
}

# Configuration information
output "gemini_model" {
  description = "Gemini model being used for content classification"
  value       = var.gemini_model
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function (MB)"
  value       = var.function_memory
}

output "function_timeout" {
  description = "Timeout for the Cloud Function (seconds)"
  value       = var.function_timeout
}

output "max_file_size_mb" {
  description = "Maximum file size that will be processed (MB)"
  value       = var.max_file_size_mb
}

# Logging information (conditional outputs)
output "logging_enabled" {
  description = "Whether detailed logging is enabled"
  value       = var.enable_logging
}

output "function_logs_bucket_name" {
  description = "Name of the function logs bucket (if logging is enabled)"
  value       = var.enable_logging ? google_storage_bucket.function_logs[0].name : null
}

output "log_retention_days" {
  description = "Number of days logs are retained"
  value       = var.log_retention_days
}

# Monitoring information (conditional outputs)
output "monitoring_enabled" {
  description = "Whether monitoring alerts are configured"
  value       = var.notification_email != ""
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email != "" ? var.notification_email : null
  sensitive   = true
}

# Resource naming information
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

# Bucket classification mapping
output "bucket_classification_mapping" {
  description = "Mapping of content types to their respective bucket names"
  value = {
    contracts     = google_storage_bucket.contracts.name
    invoices      = google_storage_bucket.invoices.name
    marketing     = google_storage_bucket.marketing.name
    miscellaneous = google_storage_bucket.miscellaneous.name
  }
}

# Upload commands for easy reference
output "upload_command_example" {
  description = "Example gsutil command to upload files to the staging bucket"
  value       = "gsutil cp your-file.pdf gs://${google_storage_bucket.staging.name}/"
}

# Verification commands
output "verification_commands" {
  description = "Commands to verify the deployment and test the system"
  value = {
    check_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.content_classifier.name} --region=${var.region} --limit=20"
    list_staging_bucket = "gsutil ls -la gs://${google_storage_bucket.staging.name}/"
    list_contracts_bucket = "gsutil ls -la gs://${google_storage_bucket.contracts.name}/"
    list_invoices_bucket = "gsutil ls -la gs://${google_storage_bucket.invoices.name}/"
    list_marketing_bucket = "gsutil ls -la gs://${google_storage_bucket.marketing.name}/"
    list_misc_bucket = "gsutil ls -la gs://${google_storage_bucket.miscellaneous.name}/"
    upload_test_file = "echo 'This is a sample contract document' | gsutil cp - gs://${google_storage_bucket.staging.name}/test-contract.txt"
  }
}

# Important URLs and links
output "important_urls" {
  description = "Important Google Cloud Console URLs for monitoring the system"
  value = {
    cloud_functions_console = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    cloud_storage_console = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    vertex_ai_console = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
    cloud_logging_console = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    cloud_monitoring_console = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

# Cost optimization information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the content classification system"
  value = {
    storage_class = "Current storage class: ${var.storage_class}. Consider NEARLINE for infrequently accessed content."
    gemini_model = "Current model: ${var.gemini_model}. Consider gemini-2.5-flash for high-volume, cost-sensitive workloads."
    function_memory = "Current memory: ${var.function_memory}MB. Monitor usage and adjust if needed."
    lifecycle_rules = "Bucket lifecycle rules are configured to automatically transition objects to cheaper storage classes."
  }
}

# Next steps and recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload test files to gs://${google_storage_bucket.staging.name}/ to verify classification",
    "2. Monitor function logs: gcloud functions logs read ${google_cloudfunctions2_function.content_classifier.name} --region=${var.region}",
    "3. Check classified files in their respective buckets using the verification commands",
    "4. Set up additional monitoring and alerting as needed",
    "5. Consider implementing additional content types by modifying the classification logic",
    "6. Review and adjust bucket lifecycle policies based on your retention requirements"
  ]
}