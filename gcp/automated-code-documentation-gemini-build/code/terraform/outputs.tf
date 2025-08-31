# Output values for the automated code documentation infrastructure
# These outputs provide important information for using and integrating with the deployed solution

# Project and environment information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name used for this deployment"
  value       = var.environment
}

# Storage resources
output "documentation_bucket_name" {
  description = "Name of the Cloud Storage bucket for documentation storage"
  value       = google_storage_bucket.documentation_storage.name
}

output "documentation_bucket_url" {
  description = "URL of the Cloud Storage bucket for documentation storage"
  value       = google_storage_bucket.documentation_storage.url
}

output "documentation_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.documentation_storage.self_link
}

# Service account information
output "service_account_email" {
  description = "Email address of the documentation automation service account"
  value       = google_service_account.doc_automation.email
}

output "service_account_unique_id" {
  description = "Unique ID of the documentation automation service account"
  value       = google_service_account.doc_automation.unique_id
}

# Cloud Function information
output "doc_processor_function_name" {
  description = "Name of the documentation processing Cloud Function"
  value       = google_cloudfunctions2_function.doc_processor.name
}

output "doc_processor_function_uri" {
  description = "URI of the documentation processing Cloud Function"
  value       = google_cloudfunctions2_function.doc_processor.service_config[0].uri
  sensitive   = true
}

output "doc_processor_function_url" {
  description = "URL of the documentation processing Cloud Function"
  value       = google_cloudfunctions2_function.doc_processor.url
}

# Notification function information (conditional)
output "notification_function_name" {
  description = "Name of the notification Cloud Function"
  value       = var.enable_notifications ? google_cloudfunctions2_function.notification_processor[0].name : null
}

output "notification_function_uri" {
  description = "URI of the notification Cloud Function"
  value       = var.enable_notifications ? google_cloudfunctions2_function.notification_processor[0].service_config[0].uri : null
  sensitive   = true
}

# Cloud Build trigger information
output "build_trigger_name" {
  description = "Name of the Cloud Build trigger for documentation generation"
  value       = var.create_build_trigger ? google_cloudbuild_trigger.documentation_generation[0].name : null
}

output "build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = var.create_build_trigger ? google_cloudbuild_trigger.documentation_generation[0].trigger_id : null
}

# Website information (conditional)
output "documentation_website_url" {
  description = "URL of the documentation website (if enabled)"
  value       = var.enable_website ? "https://storage.googleapis.com/${google_storage_bucket.documentation_storage.name}/website/index.html" : null
}

output "documentation_website_bucket_website" {
  description = "Website endpoint for the documentation bucket"
  value       = var.enable_website ? "https://${google_storage_bucket.documentation_storage.name}.storage.googleapis.com/website/index.html" : null
}

# Access information
output "storage_console_url" {
  description = "Google Cloud Console URL for the storage bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.documentation_storage.name}"
}

output "functions_console_url" {
  description = "Google Cloud Console URL for Cloud Functions"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

output "build_console_url" {
  description = "Google Cloud Console URL for Cloud Build"
  value       = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
}

# Configuration values for reference
output "enabled_apis" {
  description = "List of Google Cloud APIs that were enabled"
  value       = var.apis_to_enable
}

output "gemini_model" {
  description = "Vertex AI Gemini model used for documentation generation"
  value       = var.gemini_model
}

output "function_memory_mb" {
  description = "Memory allocation for the documentation processing function (in MB)"
  value       = var.function_memory
}

output "function_timeout_seconds" {
  description = "Timeout for the documentation processing function (in seconds)"
  value       = var.function_timeout
}

# Resource identifiers for integration
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Terraform state information
output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

# Testing and validation outputs
output "test_curl_command" {
  description = "Example curl command to test the documentation function"
  value = <<-EOT
    curl -X POST "${google_cloudfunctions2_function.doc_processor.service_config[0].uri}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      -d '{
        "repo_path": "test.py",
        "file_content": "def hello_world():\n    \"\"\"Print hello world\"\"\"\n    print(\"Hello, World!\")",
        "doc_type": "api"
      }'
  EOT
  sensitive = true
}

output "gsutil_list_command" {
  description = "Command to list documentation files in the bucket"
  value       = "gsutil ls -r gs://${google_storage_bucket.documentation_storage.name}/"
}

output "manual_trigger_command" {
  description = "Command to manually trigger documentation generation"
  value       = var.create_build_trigger ? "gcloud builds triggers run ${google_cloudbuild_trigger.documentation_generation[0].name} --region=${var.region}" : null
}

# Cost estimation guidance
output "cost_estimation_info" {
  description = "Information for estimating monthly costs"
  value = {
    storage_class          = var.storage_class
    function_memory_mb     = var.function_memory
    region                 = var.region
    versioning_enabled     = var.enable_versioning
    estimated_monthly_cost = "$5-15 for moderate usage (storage, function invocations, Vertex AI API calls)"
  }
}

# Integration endpoints
output "integration_info" {
  description = "Key information for integrating with the documentation system"
  value = {
    function_endpoint     = google_cloudfunctions2_function.doc_processor.service_config[0].uri
    storage_bucket       = google_storage_bucket.documentation_storage.name
    service_account      = google_service_account.doc_automation.email
    build_trigger_name   = var.create_build_trigger ? google_cloudbuild_trigger.documentation_generation[0].name : null
    supported_doc_types  = ["api", "readme", "comments"]
    supported_file_types = ["*.py", "*.js", "*.go", "*.java"]
  }
  sensitive = true
}