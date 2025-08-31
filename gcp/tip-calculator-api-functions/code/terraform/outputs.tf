# Output values for the GCP tip calculator API infrastructure
# These outputs provide important information about the deployed resources

# Function URL - primary endpoint for the tip calculator API
output "function_url" {
  description = "The HTTPS URL for accessing the tip calculator API"
  value       = google_cloudfunctions_function.tip_calculator.https_trigger_url
  sensitive   = false
}

# Function name for reference and management
output "function_name" {
  description = "The deployed Cloud Function name (with unique suffix)"
  value       = google_cloudfunctions_function.tip_calculator.name
}

# Project and region information
output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where the function was deployed"
  value       = var.region
}

# Function configuration details
output "function_runtime" {
  description = "The runtime environment used for the function"
  value       = google_cloudfunctions_function.tip_calculator.runtime
}

output "function_memory" {
  description = "Memory allocation for the function in MB"
  value       = google_cloudfunctions_function.tip_calculator.available_memory_mb
}

output "function_timeout" {
  description = "Timeout setting for the function in seconds"
  value       = google_cloudfunctions_function.tip_calculator.timeout
}

# Storage bucket information for source code
output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

# Function source archive details
output "source_archive_object" {
  description = "Name of the source archive object in Cloud Storage"
  value       = google_storage_bucket_object.function_source.name
}

output "source_archive_md5" {
  description = "MD5 hash of the function source archive for change detection"
  value       = data.archive_file.function_source.output_md5
}

# Function access and security information
output "allow_unauthenticated" {
  description = "Whether the function allows unauthenticated access"
  value       = var.allow_unauthenticated
}

output "ingress_settings" {
  description = "Ingress settings configured for the function"
  value       = google_cloudfunctions_function.tip_calculator.ingress_settings
}

# Scaling configuration
output "min_instances" {
  description = "Minimum number of function instances configured"
  value       = google_cloudfunctions_function.tip_calculator.min_instances
}

output "max_instances" {
  description = "Maximum number of function instances configured"
  value       = google_cloudfunctions_function.tip_calculator.max_instances
}

# Function entry point and description
output "entry_point" {
  description = "The entry point function name in the source code"
  value       = google_cloudfunctions_function.tip_calculator.entry_point
}

output "function_description" {
  description = "Description of the deployed function"
  value       = google_cloudfunctions_function.tip_calculator.description
}

# Labels applied to resources
output "function_labels" {
  description = "Labels applied to the Cloud Function"
  value       = google_cloudfunctions_function.tip_calculator.labels
}

# Service account information (if using custom service account)
output "service_account_email" {
  description = "Email of the service account used by the function"
  value       = google_cloudfunctions_function.tip_calculator.service_account_email
}

# Logging information
output "log_sink_name" {
  description = "Name of the log sink for function monitoring"
  value       = google_logging_project_sink.function_logs.name
}

output "log_sink_destination" {
  description = "Destination for function logs"
  value       = google_logging_project_sink.function_logs.destination
}

# API testing information
output "test_commands" {
  description = "Example commands for testing the deployed function"
  value = {
    # GET request example
    get_request = "curl '${google_cloudfunctions_function.tip_calculator.https_trigger_url}?bill_amount=100&tip_percentage=18&number_of_people=4'"
    
    # POST request example
    post_request = "curl -X POST '${google_cloudfunctions_function.tip_calculator.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"bill_amount\": 87.45, \"tip_percentage\": 20, \"number_of_people\": 3}'"
    
    # Function status check
    status_check = "gcloud functions describe ${google_cloudfunctions_function.tip_calculator.name} --region=${var.region} --project=${var.project_id}"
  }
}

# Resource cleanup information
output "cleanup_commands" {
  description = "Commands to clean up deployed resources"
  value = {
    # Delete function
    delete_function = "gcloud functions delete ${google_cloudfunctions_function.tip_calculator.name} --region=${var.region} --project=${var.project_id} --quiet"
    
    # Delete storage bucket
    delete_bucket = "gsutil rm -r gs://${google_storage_bucket.function_source.name}"
    
    # Terraform destroy
    terraform_destroy = "terraform destroy -auto-approve"
  }
}

# Cost information
output "cost_information" {
  description = "Cost-related information for the deployed resources"
  value = {
    pricing_note = "Cloud Functions provides 2 million free invocations per month"
    pricing_url  = "https://cloud.google.com/functions/pricing"
    storage_cost = "Cloud Storage charges apply for source code storage (typically minimal)"
    free_tier    = "This deployment should stay within Google Cloud's free tier for typical usage"
  }
}