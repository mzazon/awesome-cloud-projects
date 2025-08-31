# Terraform Outputs Configuration
# This file defines output values that are useful for integration and verification

# Project Information Outputs
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone for compute resources"
  value       = var.zone
}

# Cloud Storage Bucket Outputs
output "recipe_storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for recipe data"
  value       = google_storage_bucket.recipe_storage.name
}

output "recipe_storage_bucket_url" {
  description = "Full URL of the Cloud Storage bucket"
  value       = google_storage_bucket.recipe_storage.url
}

output "recipe_storage_bucket_self_link" {
  description = "Self-link to the Cloud Storage bucket"
  value       = google_storage_bucket.recipe_storage.self_link
}

# Cloud Functions Outputs
output "recipe_generator_function_name" {
  description = "Name of the recipe generator Cloud Function"
  value       = google_cloudfunctions_function.recipe_generator.name
}

output "recipe_generator_function_url" {
  description = "HTTP trigger URL for the recipe generator function"
  value       = google_cloudfunctions_function.recipe_generator.https_trigger_url
  sensitive   = false
}

output "recipe_generator_function_source_archive" {
  description = "Source archive location for the generator function"
  value       = "gs://${google_storage_bucket.recipe_storage.name}/${google_storage_bucket_object.generator_function_source.name}"
}

output "recipe_retriever_function_name" {
  description = "Name of the recipe retriever Cloud Function"
  value       = google_cloudfunctions_function.recipe_retriever.name
}

output "recipe_retriever_function_url" {
  description = "HTTP trigger URL for the recipe retriever function"
  value       = google_cloudfunctions_function.recipe_retriever.https_trigger_url
  sensitive   = false
}

output "recipe_retriever_function_source_archive" {
  description = "Source archive location for the retriever function"
  value       = "gs://${google_storage_bucket.recipe_storage.name}/${google_storage_bucket_object.retriever_function_source.name}"
}

# API Endpoints for Testing and Integration
output "api_endpoints" {
  description = "API endpoints for the recipe generation system"
  value = {
    generator_url = google_cloudfunctions_function.recipe_generator.https_trigger_url
    retriever_url = google_cloudfunctions_function.recipe_retriever.https_trigger_url
  }
}

# Service Account Information
output "functions_service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = data.google_app_engine_default_service_account.default.email
}

# Resource Naming Information
output "resource_name_prefix" {
  description = "Common prefix used for resource naming"
  value       = local.name_prefix
}

output "unique_suffix" {
  description = "Unique suffix used for globally unique resource names"
  value       = local.unique_suffix
}

# Vertex AI Configuration
output "vertex_ai_location" {
  description = "Location configured for Vertex AI resources"
  value       = var.vertex_ai_location
}

output "gemini_model_name" {
  description = "Name of the Gemini model configured for recipe generation"
  value       = var.gemini_model_name
}

# Security and Access Configuration
output "bucket_iam_members" {
  description = "IAM members with access to the storage bucket"
  value       = var.additional_iam_members
  sensitive   = true
}

output "function_authentication_required" {
  description = "Whether authentication is required to access the functions"
  value       = !var.allow_unauthenticated
}

# Monitoring and Logging Configuration
output "function_logging_enabled" {
  description = "Whether detailed function logging is enabled"
  value       = var.enable_function_logging
}

output "logging_sink_name" {
  description = "Name of the logging sink for function logs"
  value       = var.enable_function_logging ? google_logging_project_sink.function_logs[0].name : null
}

# Cost Management Information
output "cost_labels" {
  description = "Common labels applied to resources for cost tracking"
  value       = local.common_labels
  sensitive   = false
}

output "estimated_monthly_cost_range" {
  description = "Estimated monthly cost range for the deployed resources"
  value       = "$5-15 USD (depends on usage: Vertex AI charges per request, Cloud Functions per invocation, Storage per GB)"
}

# Function Configuration Details
output "function_configurations" {
  description = "Configuration details for deployed Cloud Functions"
  value = {
    generator = {
      memory_mb = var.generator_function_memory
      timeout_s = var.generator_function_timeout
      runtime   = var.function_runtime
    }
    retriever = {
      memory_mb = var.retriever_function_memory
      timeout_s = var.retriever_function_timeout
      runtime   = var.function_runtime
    }
  }
}

# Testing and Validation Information
output "test_commands" {
  description = "Sample commands for testing the deployed functions"
  value = {
    test_generator = "curl -X POST ${google_cloudfunctions_function.recipe_generator.https_trigger_url} -H 'Content-Type: application/json' -d '{\"ingredients\":[\"chicken\",\"broccoli\"],\"skill_level\":\"beginner\"}'"
    test_retriever = "curl '${google_cloudfunctions_function.recipe_retriever.https_trigger_url}?limit=5'"
    list_recipes   = "gsutil ls gs://${google_storage_bucket.recipe_storage.name}/recipes/"
  }
}

# Storage Configuration
output "storage_configuration" {
  description = "Configuration details for the Cloud Storage bucket"
  value = {
    storage_class      = var.bucket_storage_class
    versioning_enabled = var.bucket_versioning_enabled
    lifecycle_age_days = var.bucket_lifecycle_age
    location          = var.region
  }
}

# Enabled APIs
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this project"
  value = var.enable_api_services ? [
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com", 
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ] : []
}