# Project and configuration outputs
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

# Cloud Storage bucket outputs
output "input_bucket_name" {
  description = "Name of the Cloud Storage bucket for code repository input"
  value       = google_storage_bucket.input_bucket.name
}

output "input_bucket_url" {
  description = "URL of the input bucket for uploading code repositories"
  value       = google_storage_bucket.input_bucket.url
}

output "output_bucket_name" {
  description = "Name of the Cloud Storage bucket for generated documentation output"
  value       = google_storage_bucket.output_bucket.name
}

output "output_bucket_url" {
  description = "URL of the output bucket for accessing generated documentation"
  value       = google_storage_bucket.output_bucket.url
}

output "temp_bucket_name" {
  description = "Name of the temporary processing bucket"
  value       = google_storage_bucket.temp_bucket.name
}

output "function_source_bucket_name" {
  description = "Name of the bucket containing Cloud Function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

# Cloud Function outputs
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.adk_documentation_function.name
}

output "function_url" {
  description = "URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.adk_documentation_function.service_config[0].uri
}

output "function_location" {
  description = "Location where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.adk_documentation_function.location
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# ADK and AI configuration outputs
output "vertex_ai_location" {
  description = "Location configured for Vertex AI resources"
  value       = var.vertex_ai_location
}

output "gemini_model" {
  description = "Gemini model version configured for ADK agents"
  value       = var.gemini_model
}

# Usage and testing outputs
output "sample_repository_created" {
  description = "Whether a sample repository was created for testing"
  value       = var.create_sample_repository
}

output "upload_command" {
  description = "Command to upload a code repository for processing"
  value       = "gsutil cp your-repo.zip gs://${google_storage_bucket.input_bucket.name}/"
}

output "download_docs_command" {
  description = "Command to download generated documentation"
  value       = "gsutil cp gs://${google_storage_bucket.output_bucket.name}/your-repo.zip/README.md ./"
}

# Monitoring and logging outputs
output "monitoring_enabled" {
  description = "Whether monitoring and alerting are enabled"
  value       = var.enable_function_logging
}

output "log_level" {
  description = "Configured log level for the Cloud Function"
  value       = var.log_level
}

output "debug_mode_enabled" {
  description = "Whether debug mode is enabled"
  value       = var.enable_debug_mode
}

# Resource labeling outputs
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
  sensitive   = false
}

# Security configuration outputs
output "uniform_bucket_level_access" {
  description = "Whether uniform bucket-level access is enabled"
  value       = var.enable_uniform_bucket_level_access
}

output "encryption_enabled" {
  description = "Whether customer-managed encryption is enabled"
  value       = var.enable_encryption
}

# Service configuration outputs
output "function_memory_mb" {
  description = "Memory allocation for the Cloud Function in MB"
  value       = var.function_memory
}

output "function_timeout_seconds" {
  description = "Timeout for the Cloud Function in seconds"
  value       = var.function_timeout
}

output "function_max_instances" {
  description = "Maximum number of function instances"
  value       = var.function_max_instances
}

# Storage configuration outputs
output "storage_location" {
  description = "Location configured for Cloud Storage buckets"
  value       = var.storage_location
}

output "storage_class" {
  description = "Storage class configured for buckets"
  value       = var.storage_class
}

output "bucket_lifecycle_age_days" {
  description = "Age in days after which objects are deleted from temporary storage"
  value       = var.bucket_lifecycle_age
}

# API endpoints and integration outputs
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com"
  ]
}

# Cost and resource optimization outputs
output "cost_optimization_features" {
  description = "Cost optimization features enabled in this deployment"
  value = {
    storage_lifecycle_management = true
    function_auto_scaling        = true
    uniform_bucket_access       = var.enable_uniform_bucket_level_access
    temporary_file_cleanup      = true
    min_function_instances      = 0
  }
}

# Quick start guide
output "quick_start_guide" {
  description = "Quick start commands for using the ADK documentation system"
  value = {
    "1_upload_repository" = "gsutil cp your-code-repo.zip gs://${google_storage_bucket.input_bucket.name}/"
    "2_monitor_processing" = "gcloud functions logs read ${google_cloudfunctions2_function.adk_documentation_function.name} --gen2 --region ${var.region} --limit 20"
    "3_download_docs" = "gsutil cp gs://${google_storage_bucket.output_bucket.name}/your-code-repo.zip/README.md ./"
    "4_view_analysis" = "gsutil cp gs://${google_storage_bucket.output_bucket.name}/your-code-repo.zip/analysis_summary.json ./"
  }
}

# Infrastructure summary
output "infrastructure_summary" {
  description = "Summary of deployed infrastructure components"
  value = {
    cloud_function = {
      name     = google_cloudfunctions2_function.adk_documentation_function.name
      runtime  = var.function_runtime
      memory   = "${var.function_memory}MB"
      timeout  = "${var.function_timeout}s"
      trigger  = "Cloud Storage (${google_storage_bucket.input_bucket.name})"
    }
    storage_buckets = {
      input_bucket  = google_storage_bucket.input_bucket.name
      output_bucket = google_storage_bucket.output_bucket.name
      temp_bucket   = google_storage_bucket.temp_bucket.name
    }
    ai_configuration = {
      vertex_ai_location = var.vertex_ai_location
      gemini_model      = var.gemini_model
      adk_enabled       = true
    }
    security = {
      service_account           = google_service_account.function_sa.email
      uniform_bucket_access     = var.enable_uniform_bucket_level_access
      public_access_prevention  = "enforced"
      iam_least_privilege      = true
    }
  }
}