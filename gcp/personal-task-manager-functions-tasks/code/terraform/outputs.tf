# Output values for GCP Personal Task Manager infrastructure
# These outputs provide essential information about the deployed resources
# and enable integration with other systems or manual testing

# Function URL for API access
output "function_url" {
  description = "HTTPS URL of the deployed Cloud Function for API access"
  value       = google_cloudfunctions_function.task_manager.https_trigger_url
  sensitive   = false
}

# Function name with unique suffix
output "function_name" {
  description = "Full name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.task_manager.name
  sensitive   = false
}

# Project information
output "project_id" {
  description = "GCP project ID where resources are deployed"
  value       = var.project_id
  sensitive   = false
}

# Deployment region
output "region" {
  description = "GCP region where the Cloud Function is deployed"
  value       = var.region
  sensitive   = false
}

# Service account details
output "service_account_email" {
  description = "Email address of the service account used by the Cloud Function"
  value       = google_service_account.task_manager_sa.email
  sensitive   = false
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.task_manager_sa.unique_id
  sensitive   = false
}

# Storage bucket information
output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
  sensitive   = false
}

output "source_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
  sensitive   = false
}

# Function configuration details
output "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  value       = google_cloudfunctions_function.task_manager.available_memory_mb
  sensitive   = false
}

output "function_timeout" {
  description = "Timeout configuration for the Cloud Function in seconds"
  value       = google_cloudfunctions_function.task_manager.timeout
  sensitive   = false
}

output "function_runtime" {
  description = "Runtime version used by the Cloud Function"
  value       = google_cloudfunctions_function.task_manager.runtime
  sensitive   = false
}

# Resource naming information
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
  sensitive   = false
}

# API endpoints documentation
output "api_endpoints" {
  description = "Available API endpoints and their HTTP methods"
  value = {
    list_tasks   = "GET ${google_cloudfunctions_function.task_manager.https_trigger_url}/tasks"
    create_task  = "POST ${google_cloudfunctions_function.task_manager.https_trigger_url}/tasks"
    delete_task  = "DELETE ${google_cloudfunctions_function.task_manager.https_trigger_url}/tasks/{task_id}"
    health_check = "GET ${google_cloudfunctions_function.task_manager.https_trigger_url}/health"
  }
  sensitive = false
}

# cURL examples for testing
output "curl_examples" {
  description = "Example cURL commands for testing the API"
  value = {
    list_tasks = "curl -X GET '${google_cloudfunctions_function.task_manager.https_trigger_url}/tasks'"
    create_basic_task = "curl -X POST '${google_cloudfunctions_function.task_manager.https_trigger_url}/tasks' -H 'Content-Type: application/json' -d '{\"title\": \"Test Task\", \"notes\": \"Created via API\"}'"
    health_check = "curl -X GET '${google_cloudfunctions_function.task_manager.https_trigger_url}/health'"
  }
  sensitive = false
}

# Labels applied to resources
output "resource_labels" {
  description = "Labels applied to all created resources"
  value       = local.common_labels
  sensitive   = false
}

# Enabled APIs
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
  sensitive = false
}

# Cost estimation information
output "cost_information" {
  description = "Cost-related information and optimization tips"
  value = {
    function_pricing_tier = var.function_memory <= 256 ? "Low cost tier" : "Higher cost tier"
    estimated_monthly_cost = var.function_memory <= 256 ? "$0.01-$0.10 for light usage" : "$0.05-$0.50 for light usage"
    optimization_tips = [
      "Use minimum memory allocation (256MB) for basic operations",
      "Set min_instances to 0 to avoid idle costs",
      "Monitor usage with Cloud Monitoring to optimize resources",
      "Clean up old source code versions in Cloud Storage"
    ]
  }
  sensitive = false
}

# Security information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    public_access_enabled = var.enable_public_access
    service_account_principle = "tasks.googleapis.com access only"
    https_enforced = "SECURE_OPTIONAL - allows both HTTP and HTTPS"
    cors_enabled = "Enabled for all origins (*)"
  }
  sensitive = false
}

# Monitoring and logging URLs
output "monitoring_links" {
  description = "Direct links to monitoring and logging dashboards"
  value = {
    function_logs = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.task_manager.name}?project=${var.project_id}&tab=logs"
    function_metrics = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.task_manager.name}?project=${var.project_id}&tab=metrics"
    cloud_console = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
  }
  sensitive = false
}

# Troubleshooting information
output "troubleshooting_guide" {
  description = "Common troubleshooting steps and diagnostic commands"
  value = {
    test_function_locally = "functions-framework --target=task_manager --debug"
    check_function_logs = "gcloud functions logs read ${google_cloudfunctions_function.task_manager.name} --region=${var.region}"
    verify_apis_enabled = "gcloud services list --enabled --filter='name:(cloudfunctions.googleapis.com OR tasks.googleapis.com)'"
    test_service_account = "gcloud auth activate-service-account --key-file=credentials.json"
  }
  sensitive = false
}