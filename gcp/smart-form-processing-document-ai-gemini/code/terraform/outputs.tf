# Outputs for Smart Form Processing Infrastructure
# This file defines outputs that provide important information about the deployed resources

# ================================
# Project Information
# ================================

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

# ================================
# Cloud Storage Buckets
# ================================

output "input_bucket_name" {
  description = "Name of the Cloud Storage bucket for uploading forms"
  value       = google_storage_bucket.input_bucket.name
}

output "input_bucket_url" {
  description = "URL of the input bucket for uploading forms"
  value       = google_storage_bucket.input_bucket.url
}

output "output_bucket_name" {
  description = "Name of the Cloud Storage bucket for processed results"
  value       = google_storage_bucket.output_bucket.name
}

output "output_bucket_url" {
  description = "URL of the output bucket for processed results"
  value       = google_storage_bucket.output_bucket.url
}

# ================================
# Document AI Processor
# ================================

output "document_ai_processor_id" {
  description = "ID of the Document AI processor for form parsing"
  value       = google_document_ai_processor.form_parser.name
}

output "document_ai_processor_display_name" {
  description = "Display name of the Document AI processor"
  value       = google_document_ai_processor.form_parser.display_name
}

output "document_ai_processor_type" {
  description = "Type of the Document AI processor"
  value       = google_document_ai_processor.form_parser.type
}

# ================================
# Cloud Function
# ================================

output "cloud_function_name" {
  description = "Name of the Cloud Function for form processing"
  value       = google_cloudfunctions2_function.form_processor.name
}

output "cloud_function_url" {
  description = "URL of the Cloud Function (if HTTP trigger enabled)"
  value       = google_cloudfunctions2_function.form_processor.service_config[0].uri
}

output "cloud_function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# ================================
# Service Account
# ================================

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_service_account_unique_id" {
  description = "Unique ID of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.unique_id
}

# ================================
# Testing and Usage Information
# ================================

output "gsutil_upload_command" {
  description = "Command to upload a test form to trigger processing"
  value       = "gsutil cp your-form.pdf gs://${google_storage_bucket.input_bucket.name}/"
}

output "gsutil_list_results_command" {
  description = "Command to list processed results"
  value       = "gsutil ls gs://${google_storage_bucket.output_bucket.name}/processed/"
}

output "gcloud_function_logs_command" {
  description = "Command to view Cloud Function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions2_function.form_processor.name} --region=${var.region} --limit=50"
}

# ================================
# Resource Identifiers
# ================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "environment" {
  description = "Environment name used for resource labeling"
  value       = var.environment
}

# ================================
# Configuration Summary
# ================================

output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    project_id                = var.project_id
    region                   = var.region
    environment              = var.environment
    input_bucket             = google_storage_bucket.input_bucket.name
    output_bucket            = google_storage_bucket.output_bucket.name
    function_name            = google_cloudfunctions2_function.form_processor.name
    document_ai_processor    = google_document_ai_processor.form_parser.name
    function_runtime         = var.function_runtime
    function_memory          = var.function_memory
    function_timeout         = var.function_timeout
    vertex_ai_model          = var.vertex_ai_model
    storage_class            = var.storage_class
    uniform_bucket_access    = var.enable_uniform_bucket_level_access
    public_access_prevention = var.enable_public_access_prevention
  }
}

# ================================
# Quick Start Guide
# ================================

output "quick_start_guide" {
  description = "Quick start commands for testing the deployed infrastructure"
  value = <<-EOT
## Quick Start Guide

### 1. Upload a test form:
gsutil cp test-form.pdf gs://${google_storage_bucket.input_bucket.name}/

### 2. Monitor function execution:
gcloud functions logs read ${google_cloudfunctions2_function.form_processor.name} --region=${var.region} --limit=20

### 3. Check processed results:
gsutil ls gs://${google_storage_bucket.output_bucket.name}/processed/

### 4. Download and view results:
gsutil cp gs://${google_storage_bucket.output_bucket.name}/processed/test-form_results.json .
cat test-form_results.json | jq .

### 5. Clean up test files:
gsutil rm gs://${google_storage_bucket.input_bucket.name}/test-form.pdf
gsutil rm gs://${google_storage_bucket.output_bucket.name}/processed/test-form_results.json

## Configuration Details:
- Document AI Processor: ${google_document_ai_processor.form_parser.name}
- Function Runtime: ${var.function_runtime}
- Memory Allocation: ${var.function_memory}MB
- Timeout: ${var.function_timeout}s
- Vertex AI Model: ${var.vertex_ai_model}
EOT
}

# ================================
# Cost Monitoring Information
# ================================

output "cost_monitoring_info" {
  description = "Information about cost monitoring and optimization"
  value = {
    bucket_lifecycle_days = var.bucket_lifecycle_days
    storage_class        = var.storage_class
    function_min_instances = var.function_min_instances
    function_max_instances = var.function_max_instances
    cost_factors = [
      "Document AI charges per page processed",
      "Vertex AI Gemini charges per token",
      "Cloud Functions charges per invocation and compute time",
      "Cloud Storage charges for storage and operations",
      "Objects are automatically deleted after ${var.bucket_lifecycle_days} days"
    ]
  }
}