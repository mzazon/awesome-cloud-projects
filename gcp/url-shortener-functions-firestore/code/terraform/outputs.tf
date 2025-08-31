# Outputs for GCP URL Shortener Infrastructure
# Provides important resource information after deployment

# Cloud Function Outputs
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.url_shortener.name
}

output "function_url" {
  description = "HTTPS URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.url_shortener.service_config[0].uri
  sensitive   = false
}

output "function_trigger_url" {
  description = "Public trigger URL for the Cloud Function (same as function_url)"
  value       = google_cloudfunctions2_function.url_shortener.url
}

output "function_location" {
  description = "Location where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.url_shortener.location
}

output "function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Firestore Database Outputs
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.url_shortener_db.name
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.url_shortener_db.location_id
}

output "firestore_database_type" {
  description = "Type of the Firestore database"
  value       = google_firestore_database.url_shortener_db.type
}

output "firestore_database_id" {
  description = "Full resource ID of the Firestore database"
  value       = google_firestore_database.url_shortener_db.id
}

# Storage Bucket Outputs
output "source_bucket_name" {
  description = "Name of the source code storage bucket"
  value       = google_storage_bucket.function_source.name
}

output "source_bucket_url" {
  description = "URL of the source code storage bucket"
  value       = google_storage_bucket.function_source.url
}

output "source_archive_object" {
  description = "Name of the source code archive object"
  value       = google_storage_bucket_object.function_source.name
}

# API and Endpoint Information
output "api_endpoints" {
  description = "Available API endpoints for the URL shortener"
  value = {
    base_url        = google_cloudfunctions2_function.url_shortener.service_config[0].uri
    shorten_url     = "${google_cloudfunctions2_function.url_shortener.service_config[0].uri}/shorten"
    redirect_format = "${google_cloudfunctions2_function.url_shortener.service_config[0].uri}/{short_id}"
    documentation   = google_cloudfunctions2_function.url_shortener.service_config[0].uri
  }
}

# Project Information
output "project_id" {
  description = "Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region used for deployment"
  value       = var.region
}

# Usage Examples
output "usage_examples" {
  description = "Examples of how to use the URL shortener API"
  value = {
    curl_shorten = "curl -X POST ${google_cloudfunctions2_function.url_shortener.service_config[0].uri}/shorten -H 'Content-Type: application/json' -d '{\"url\": \"https://example.com\"}'"
    curl_redirect = "curl -I ${google_cloudfunctions2_function.url_shortener.service_config[0].uri}/ABC123"
    javascript_example = jsonencode({
      method = "POST"
      url    = "${google_cloudfunctions2_function.url_shortener.service_config[0].uri}/shorten"
      headers = {
        "Content-Type" = "application/json"
      }
      body = jsonencode({
        url = "https://example.com"
      })
    })
  }
}

# Resource Metadata
output "deployment_metadata" {
  description = "Metadata about the deployment"
  value = {
    function_runtime          = var.runtime
    function_memory          = var.function_memory
    function_timeout         = var.function_timeout
    function_max_instances   = var.function_max_instances
    function_min_instances   = var.function_min_instances
    firestore_pitr_enabled   = var.enable_point_in_time_recovery
    delete_protection        = var.enable_delete_protection
    unauthenticated_access   = var.allow_unauthenticated_access
    cors_enabled            = length(var.cors_allowed_origins) > 0
    labels                  = var.resource_labels
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information for cost optimization"
  value = {
    function_billing_model = "Pay-per-invocation and compute time"
    function_free_tier    = "2 million invocations per month"
    firestore_free_tier   = "50,000 reads and 20,000 writes per day"
    storage_free_tier     = "5 GB storage per month"
    estimated_monthly_cost = "Typically under $1/month for small-scale usage"
    optimization_tips = [
      "Set min_instances to 0 for cost savings with cold starts",
      "Use appropriate memory allocation based on workload",
      "Monitor and adjust timeout settings",
      "Leverage Firestore free tier limits",
      "Consider regional deployment for lower latency and costs"
    ]
  }
}

# Security and Monitoring
output "security_considerations" {
  description = "Security and monitoring recommendations"
  value = {
    function_service_account = google_service_account.function_sa.email
    firestore_security_rules = "Configured to allow public reads, prevent public writes"
    monitoring_dashboard     = "Available in Google Cloud Console"
    logging_location        = "Cloud Logging with function name filter"
    recommended_monitoring = [
      "Function invocation count and errors",
      "Function execution time and memory usage",
      "Firestore read/write operations",
      "HTTP response codes and latency"
    ]
  }
}