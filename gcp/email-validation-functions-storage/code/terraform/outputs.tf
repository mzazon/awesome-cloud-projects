# Cloud Function outputs
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.email_validator.name
}

output "function_url" {
  description = "HTTP trigger URL for the email validation function"
  value       = google_cloudfunctions2_function.email_validator.service_config[0].uri
}

output "function_location" {
  description = "Location where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.email_validator.location
}

output "function_state" {
  description = "Current state of the Cloud Function"
  value       = google_cloudfunctions2_function.email_validator.state
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Cloud Storage outputs
output "logs_bucket_name" {
  description = "Name of the Cloud Storage bucket for validation logs"
  value       = google_storage_bucket.validation_logs.name
}

output "logs_bucket_url" {
  description = "URL of the Cloud Storage bucket for validation logs"
  value       = google_storage_bucket.validation_logs.url
}

output "logs_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket for validation logs"
  value       = google_storage_bucket.validation_logs.self_link
}

output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

# Configuration outputs
output "project_id" {
  description = "Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone configuration"
  value       = var.zone
}

# Testing and validation outputs
output "test_curl_command" {
  description = "Example curl command to test the email validation API"
  value = <<-EOT
    # Test with a valid email
    curl -X POST \
      -H "Content-Type: application/json" \
      -d '{"email":"test@gmail.com"}' \
      ${google_cloudfunctions2_function.email_validator.service_config[0].uri}
    
    # Test with an invalid email
    curl -X POST \
      -H "Content-Type: application/json" \
      -d '{"email":"invalid-email"}' \
      ${google_cloudfunctions2_function.email_validator.service_config[0].uri}
  EOT
}

output "logs_gsutil_command" {
  description = "GSUtil command to view validation logs"
  value       = "gsutil ls -r gs://${google_storage_bucket.validation_logs.name}/validations/"
}

# Security and access outputs
output "function_authentication_required" {
  description = "Whether the function requires authentication for invocation"
  value       = !var.allow_unauthenticated_invocations
}

output "bucket_uniform_access_enabled" {
  description = "Whether uniform bucket-level access is enabled"
  value       = var.enable_uniform_bucket_access
}

output "bucket_versioning_enabled" {
  description = "Whether object versioning is enabled on the logs bucket"
  value       = var.enable_versioning
}

# Cost optimization outputs
output "lifecycle_policies_enabled" {
  description = "Whether cost optimization lifecycle policies are enabled"
  value       = var.enable_cost_optimization
}

output "nearline_transition_days" {
  description = "Number of days after which logs transition to NEARLINE storage"
  value       = var.lifecycle_age_nearline
}

output "deletion_days" {
  description = "Number of days after which logs are automatically deleted"
  value       = var.lifecycle_age_delete
}

# Monitoring and observability outputs
output "cloud_logging_link" {
  description = "Google Cloud Console link to view function logs"
  value = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions2_function.email_validator.name}%22?project=${var.project_id}"
}

output "cloud_monitoring_link" {
  description = "Google Cloud Console link to view function metrics"
  value = "https://console.cloud.google.com/monitoring/dashboards/custom?project=${var.project_id}&dashboardResource=projects%2F${var.project_id}%2Fdashboards"
}

output "function_console_link" {
  description = "Google Cloud Console link to view the Cloud Function"
  value = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.email_validator.name}?project=${var.project_id}"
}

output "storage_console_link" {
  description = "Google Cloud Console link to view the Cloud Storage bucket"
  value = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.validation_logs.name}?project=${var.project_id}"
}

# Resource identifiers for integration
output "function_id" {
  description = "Full resource ID of the Cloud Function"
  value       = google_cloudfunctions2_function.email_validator.id
}

output "logs_bucket_id" {
  description = "Full resource ID of the logs storage bucket"
  value       = google_storage_bucket.validation_logs.id
}

output "service_account_id" {
  description = "Full resource ID of the function service account"
  value       = google_service_account.function_sa.id
}

# Deployment metadata
output "deployment_timestamp" {
  description = "Timestamp when the resources were deployed"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for deployment"
  value       = terraform.workspace
}

output "random_suffix" {
  description = "Random suffix used for globally unique resource names"
  value       = random_id.suffix.hex
}

# API endpoints for programmatic access
output "validation_api_endpoint" {
  description = "Complete API endpoint information for email validation"
  value = {
    url    = google_cloudfunctions2_function.email_validator.service_config[0].uri
    method = "POST"
    headers = {
      "Content-Type" = "application/json"
    }
    example_payload = {
      email = "user@example.com"
    }
    cors_enabled = true
  }
}

# Resource costs and optimization info
output "estimated_monthly_costs" {
  description = "Estimated monthly costs breakdown (USD, approximate)"
  value = {
    cloud_function_invocations = "First 2M invocations free, then $0.0000004 per invocation"
    cloud_function_compute     = "First 400,000 GB-seconds free, then $0.0000025 per GB-second"
    cloud_storage_standard     = "$0.020 per GB per month"
    cloud_storage_nearline     = "$0.010 per GB per month (after ${var.lifecycle_age_nearline} days)"
    cloud_logging              = "First 50 GB free, then $0.50 per GB"
    note                       = "Actual costs depend on usage patterns and current GCP pricing"
  }
}