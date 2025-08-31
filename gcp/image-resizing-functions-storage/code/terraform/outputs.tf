# Output values for GCP image resizing infrastructure

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Storage bucket outputs
output "original_images_bucket" {
  description = "Details of the original images storage bucket"
  value = {
    name         = google_storage_bucket.original_images.name
    url          = google_storage_bucket.original_images.url
    self_link    = google_storage_bucket.original_images.self_link
    location     = google_storage_bucket.original_images.location
    storage_class = google_storage_bucket.original_images.storage_class
  }
}

output "resized_images_bucket" {
  description = "Details of the resized images storage bucket"
  value = {
    name         = google_storage_bucket.resized_images.name
    url          = google_storage_bucket.resized_images.url
    self_link    = google_storage_bucket.resized_images.self_link
    location     = google_storage_bucket.resized_images.location
    storage_class = google_storage_bucket.resized_images.storage_class
  }
}

output "function_source_bucket" {
  description = "Details of the function source code bucket"
  value = {
    name      = google_storage_bucket.function_source.name
    url       = google_storage_bucket.function_source.url
    self_link = google_storage_bucket.function_source.self_link
  }
}

# Cloud Function outputs
output "resize_function" {
  description = "Details of the image resizing Cloud Function"
  value = {
    name            = google_cloudfunctions2_function.resize_function.name
    url             = google_cloudfunctions2_function.resize_function.url
    state           = google_cloudfunctions2_function.resize_function.state
    location        = google_cloudfunctions2_function.resize_function.location
    runtime         = var.function_config.runtime
    entry_point     = var.function_config.entry_point
    memory_mb       = var.function_config.memory_mb
    timeout_seconds = var.function_config.timeout_seconds
    max_instances   = var.function_config.max_instances
  }
}

output "function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = local.function_service_account
}

# Configuration outputs
output "thumbnail_sizes" {
  description = "Configured thumbnail sizes that will be generated"
  value       = var.thumbnail_sizes
}

output "supported_image_formats" {
  description = "List of supported image file formats"
  value       = var.supported_image_formats
}

# Upload instructions
output "upload_instructions" {
  description = "Instructions for uploading images to trigger processing"
  value = {
    upload_command = "gsutil cp your-image.jpg gs://${google_storage_bucket.original_images.name}/"
    check_results  = "gsutil ls gs://${google_storage_bucket.resized_images.name}/"
    view_logs     = "gcloud functions logs read ${google_cloudfunctions2_function.resize_function.name} --gen2 --region=${var.region} --limit=20"
  }
}

# Cost estimation information
output "estimated_costs" {
  description = "Estimated monthly costs for typical usage patterns"
  value = {
    note = "Costs depend on usage volume. Cloud Functions offers 2M free invocations/month."
    storage_standard_per_gb_month = "$0.020"
    function_invocations_per_million = "$0.40"
    function_compute_time_per_gb_second = "$0.0000025"
    networking_egress_per_gb = "$0.12"
  }
}

# Security and compliance outputs
output "security_configuration" {
  description = "Security settings applied to the infrastructure"
  value = {
    uniform_bucket_level_access = var.enable_uniform_bucket_level_access
    bucket_versioning_enabled  = true
    iam_principle_least_privilege = "Service account has minimal required permissions"
    function_timeout_limit     = "${var.function_config.timeout_seconds} seconds"
    max_concurrent_executions  = var.function_config.max_instances
  }
}

# Monitoring and logging outputs
output "monitoring_links" {
  description = "Links to monitoring and logging resources in Google Cloud Console"
  value = {
    function_logs    = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.resize_function.name}?project=${var.project_id}&tab=logs"
    function_metrics = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.resize_function.name}?project=${var.project_id}&tab=metrics"
    storage_browser  = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    cloud_logging   = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  }
}

# Development and testing outputs
output "testing_commands" {
  description = "Commands for testing the image resizing functionality"
  value = {
    create_test_image = <<-EOT
      python3 -c "
      from PIL import Image
      img = Image.new('RGB', (1200, 800), color='red')
      img.save('test-image.jpg', 'JPEG')
      print('Test image created: test-image.jpg')
      "
    EOT
    
    upload_test_image = "gsutil cp test-image.jpg gs://${google_storage_bucket.original_images.name}/"
    
    check_processing = <<-EOT
      # Wait 30 seconds for processing, then check results
      sleep 30 && gsutil ls -l gs://${google_storage_bucket.resized_images.name}/
    EOT
    
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.resize_function.name} --gen2 --region=${var.region} --limit=20"
    
    download_results = "gsutil -m cp gs://${google_storage_bucket.resized_images.name}/* ./resized-images/"
  }
}

# Environment-specific outputs
output "environment_info" {
  description = "Environment-specific information and configurations"
  value = {
    environment = var.environment
    labels      = local.common_labels
    apis_enabled = var.enable_apis ? [
      "cloudfunctions.googleapis.com",
      "storage.googleapis.com", 
      "eventarc.googleapis.com",
      "cloudbuild.googleapis.com",
      "run.googleapis.com"
    ] : ["APIs management disabled - assuming pre-enabled"]
  }
}