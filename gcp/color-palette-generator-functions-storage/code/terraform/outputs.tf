# outputs.tf
# Output values for Color Palette Generator infrastructure

output "project_id" {
  description = "The Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.palette_generator.name
}

output "function_url" {
  description = "HTTP URL of the Cloud Function for color palette generation"
  value       = google_cloudfunctions_function.palette_generator.https_trigger_url
  sensitive   = false
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions_function.palette_generator.region
}

output "function_runtime" {
  description = "Runtime used by the Cloud Function"
  value       = google_cloudfunctions_function.palette_generator.runtime
}

output "bucket_name" {
  description = "Name of the Cloud Storage bucket for palette storage"
  value       = google_storage_bucket.palette_bucket.name
}

output "bucket_url" {
  description = "Public URL of the Cloud Storage bucket"
  value       = google_storage_bucket.palette_bucket.url
}

output "bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.palette_bucket.location
}

output "bucket_storage_class" {
  description = "Storage class of the palette bucket"
  value       = google_storage_bucket.palette_bucket.storage_class
}

output "public_access_enabled" {
  description = "Whether public read access is enabled on the storage bucket"
  value       = var.enable_public_access
}

output "function_service_account" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  value       = google_cloudfunctions_function.palette_generator.available_memory_mb
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function in seconds"
  value       = google_cloudfunctions_function.palette_generator.timeout
}

# URLs for testing and validation
output "test_urls" {
  description = "URLs for testing the color palette generator"
  value = {
    function_url = google_cloudfunctions_function.palette_generator.https_trigger_url
    test_command = "curl -X POST '${google_cloudfunctions_function.palette_generator.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"base_color\": \"#3498db\"}'"
    bucket_url   = "https://storage.googleapis.com/${google_storage_bucket.palette_bucket.name}/palettes/"
  }
}

# Resource identifiers for management and monitoring
output "resource_ids" {
  description = "Resource identifiers for monitoring and management"
  value = {
    function_id     = google_cloudfunctions_function.palette_generator.id
    bucket_id       = google_storage_bucket.palette_bucket.id
    service_account = google_service_account.function_sa.name
    random_suffix   = random_id.suffix.hex
  }
  sensitive = false
}

# Labels applied to resources
output "resource_labels" {
  description = "Labels applied to all created resources"
  value       = local.common_labels
}

# Storage information
output "storage_info" {
  description = "Cloud Storage bucket information and access details"
  value = {
    bucket_name    = google_storage_bucket.palette_bucket.name
    public_url     = "https://storage.googleapis.com/${google_storage_bucket.palette_bucket.name}"
    console_url    = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.palette_bucket.name}"
    versioning     = google_storage_bucket.palette_bucket.versioning[0].enabled
    uniform_access = google_storage_bucket.palette_bucket.uniform_bucket_level_access
  }
}

# Function configuration details
output "function_config" {
  description = "Cloud Function configuration details"
  value = {
    name                  = google_cloudfunctions_function.palette_generator.name
    runtime              = google_cloudfunctions_function.palette_generator.runtime
    entry_point          = google_cloudfunctions_function.palette_generator.entry_point
    memory_mb            = google_cloudfunctions_function.palette_generator.available_memory_mb
    timeout_seconds      = google_cloudfunctions_function.palette_generator.timeout
    service_account      = google_cloudfunctions_function.palette_generator.service_account_email
    trigger_type         = "HTTP"
    public_access        = true
  }
}

# Deployment information
output "deployment_info" {
  description = "Information about the deployment for documentation"
  value = {
    terraform_version = ">= 1.0"
    provider_versions = {
      google = "~> 5.0"
      archive = "~> 2.4"
      random = "~> 3.5"
    }
    deployment_time = timestamp()
    resource_count = {
      functions = 1
      buckets = 2
      service_accounts = 1
      iam_bindings = 2
    }
  }
}