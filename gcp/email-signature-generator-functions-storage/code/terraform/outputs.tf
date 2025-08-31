# Output values for the Email Signature Generator solution
# These outputs provide essential information for accessing and using the deployed resources

output "function_url" {
  description = "The HTTPS URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.signature_generator.url
}

output "function_name" {
  description = "The name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.signature_generator.name
}

output "function_location" {
  description = "The location/region of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.signature_generator.location
}

output "bucket_name" {
  description = "The name of the Cloud Storage bucket storing signatures"
  value       = google_storage_bucket.signature_storage.name
}

output "bucket_url" {
  description = "The gs:// URL of the Cloud Storage bucket"
  value       = google_storage_bucket.signature_storage.url
}

output "bucket_self_link" {
  description = "The self link of the Cloud Storage bucket"
  value       = google_storage_bucket.signature_storage.self_link
}

output "source_bucket_name" {
  description = "The name of the Cloud Storage bucket storing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_service_account_email" {
  description = "The email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

# API Testing Information
output "api_usage_examples" {
  description = "Examples of how to use the signature generation API"
  value = {
    curl_post_example = "curl -X POST '${google_cloudfunctions2_function.signature_generator.url}' -H 'Content-Type: application/json' -d '{\"name\":\"John Doe\",\"title\":\"Software Engineer\",\"company\":\"Example Corp\",\"email\":\"john@example.com\",\"phone\":\"+1 (555) 123-4567\",\"website\":\"https://example.com\"}'"
    curl_get_example  = "curl '${google_cloudfunctions2_function.signature_generator.url}?name=John%20Doe&title=Software%20Engineer&company=Example%20Corp&email=john@example.com'"
    json_payload_format = jsonencode({
      name    = "John Doe"
      title   = "Software Engineer"
      company = "Example Corp"
      email   = "john@example.com"
      phone   = "+1 (555) 123-4567"
      website = "https://example.com"
    })
  }
}

# Resource Information for Monitoring and Management
output "enabled_apis" {
  description = "List of Google Cloud APIs that were enabled for this deployment"
  value = [
    google_project_service.cloudfunctions.service,
    google_project_service.storage.service,
    google_project_service.cloudbuild.service,
    google_project_service.run.service
  ]
}

output "resource_labels" {
  description = "The labels applied to all resources in this deployment"
  value       = var.labels
}

# Cost and Usage Information
output "cost_optimization_notes" {
  description = "Information about cost optimization and free tier usage"
  value = {
    function_free_tier  = "Cloud Functions includes 2M invocations per month in free tier"
    storage_free_tier   = "Cloud Storage includes 5GB storage per month in free tier"
    pricing_factors     = "Costs based on function invocations, execution time, and storage usage"
    optimization_tips   = "Enable lifecycle policies and monitor usage to optimize costs"
  }
}

# Security and Access Information
output "security_configuration" {
  description = "Security configuration details for the deployment"
  value = {
    function_authentication = var.allow_unauthenticated ? "Unauthenticated access enabled" : "Authentication required"
    bucket_public_access    = "Signature files are publicly readable via HTTPS URLs"
    service_account_roles   = "Function uses custom service account with minimal required permissions"
    cors_enabled           = "CORS headers configured for web application integration"
  }
}

# Deployment Status and Health
output "deployment_status" {
  description = "Status information about the deployed resources"
  value = {
    function_state       = google_cloudfunctions2_function.signature_generator.state
    function_update_time = google_cloudfunctions2_function.signature_generator.update_time
    bucket_creation_time = google_storage_bucket.signature_storage.time_created
  }
}