# Output values for GCP file sharing infrastructure
# These outputs provide important information for using and integrating with the deployed resources

# Project and location information
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

# Cloud Storage bucket information
output "file_bucket_name" {
  description = "Name of the Cloud Storage bucket for file storage"
  value       = google_storage_bucket.file_bucket.name
}

output "file_bucket_url" {
  description = "URL of the Cloud Storage bucket for file storage"
  value       = google_storage_bucket.file_bucket.url
}

output "file_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket for file storage"
  value       = google_storage_bucket.file_bucket.self_link
}

# Cloud Functions information
output "upload_function_name" {
  description = "Name of the file upload Cloud Function"
  value       = google_cloudfunctions2_function.upload_function.name
}

output "upload_function_url" {
  description = "HTTP trigger URL for the file upload function"
  value       = google_cloudfunctions2_function.upload_function.service_config[0].uri
}

output "link_function_name" {
  description = "Name of the link generation Cloud Function"
  value       = google_cloudfunctions2_function.link_function.name
}

output "link_function_url" {
  description = "HTTP trigger URL for the link generation function"
  value       = google_cloudfunctions2_function.link_function.service_config[0].uri
}

# Service account information
output "service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.email
}

output "service_account_id" {
  description = "ID of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.account_id
}

# Configuration values
output "max_file_size_mb" {
  description = "Maximum allowed file size in MB"
  value       = var.max_file_size_mb
}

output "allowed_file_extensions" {
  description = "List of allowed file extensions for uploads"
  value       = var.allowed_file_extensions
}

output "signed_url_expiration_hours" {
  description = "Expiration time for signed URLs in hours"
  value       = var.signed_url_expiration_hours
}

# Web interface configuration
output "web_interface_config" {
  description = "Configuration object for web interface integration"
  value = {
    upload_url    = google_cloudfunctions2_function.upload_function.service_config[0].uri
    link_url      = google_cloudfunctions2_function.link_function.service_config[0].uri
    bucket_name   = google_storage_bucket.file_bucket.name
    project_id    = var.project_id
    region        = var.region
  }
}

# Curl command examples
output "curl_upload_example" {
  description = "Example curl command for uploading a file"
  value = "curl -X POST -F \"file=@your-file.txt\" ${google_cloudfunctions2_function.upload_function.service_config[0].uri}"
}

output "curl_link_example" {
  description = "Example curl command for generating a shareable link"
  value = "curl -X POST -H \"Content-Type: application/json\" -d '{\"filename\":\"your-file.txt\"}' ${google_cloudfunctions2_function.link_function.service_config[0].uri}"
}

# Resource identifiers for external references
output "resource_ids" {
  description = "Map of resource identifiers for external references"
  value = {
    file_bucket_id      = google_storage_bucket.file_bucket.id
    source_bucket_id    = google_storage_bucket.source_bucket.id
    upload_function_id  = google_cloudfunctions2_function.upload_function.id
    link_function_id    = google_cloudfunctions2_function.link_function.id
    service_account_id  = google_service_account.function_service_account.id
  }
}

# Monitoring and logging information
output "monitoring_info" {
  description = "Information for monitoring and logging the deployed resources"
  value = {
    upload_function_logs = "gcloud logging read \"resource.type=cloud_function AND resource.labels.function_name=${google_cloudfunctions2_function.upload_function.name}\" --project=${var.project_id}"
    link_function_logs   = "gcloud logging read \"resource.type=cloud_function AND resource.labels.function_name=${google_cloudfunctions2_function.link_function.name}\" --project=${var.project_id}"
    bucket_access_logs   = "Access logs are available in Cloud Logging for bucket: ${google_storage_bucket.file_bucket.name}"
  }
}

# Cost optimization information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed resources"
  value = {
    storage_class = "Current storage class: ${var.file_storage_class}. Consider NEARLINE or COLDLINE for infrequently accessed files."
    function_memory = "Current function memory: ${var.function_memory}. Optimize based on actual usage patterns."
    lifecycle_rules = "Automatic lifecycle rules are configured to move files to cheaper storage classes after 30 and 90 days."
  }
}

# Security information
output "security_info" {
  description = "Security configuration information"
  value = {
    bucket_access = "Uniform bucket-level access is ${var.enable_uniform_bucket_access ? "enabled" : "disabled"}"
    public_access = "Public access prevention is enforced on the storage bucket"
    cors_origins = "CORS is configured for origins: ${join(", ", var.cors_origins)}"
    signed_urls = "Signed URLs expire after ${var.signed_url_expiration_hours} hour(s)"
  }
}