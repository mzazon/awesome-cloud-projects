# Cloud Function outputs
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.form_validation_function.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.form_validation_function.service_config[0].uri
}

output "function_location" {
  description = "Location where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.form_validation_function.location
}

output "function_service_account" {
  description = "Service account email used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Firestore outputs
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.form_validation_db.name
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.form_validation_db.location_id
}

output "firestore_database_type" {
  description = "Type of the Firestore database (FIRESTORE_NATIVE or DATASTORE_MODE)"
  value       = google_firestore_database.form_validation_db.type
}

# Storage outputs
output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

# Project configuration outputs
output "project_id" {
  description = "Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

# API endpoints and testing information
output "test_curl_command" {
  description = "Sample curl command to test the form validation function"
  value = <<-EOT
    curl -X POST "${google_cloudfunctions2_function.form_validation_function.service_config[0].uri}" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "John Smith",
        "email": "john@example.com",
        "phone": "555-123-4567",
        "message": "Hello, this is a test message for the form validation system."
      }'
  EOT
}

output "firestore_console_url" {
  description = "URL to view Firestore data in Google Cloud Console"
  value       = "https://console.cloud.google.com/firestore/data?project=${var.project_id}"
}

output "function_logs_url" {
  description = "URL to view Cloud Function logs in Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.form_validation_function.name}?project=${var.project_id}&tab=logs"
}

# Resource identifiers for integration
output "function_id" {
  description = "Full resource ID of the Cloud Function"
  value       = google_cloudfunctions2_function.form_validation_function.id
}

output "firestore_database_id" {
  description = "Full resource ID of the Firestore database"
  value       = google_firestore_database.form_validation_db.id
}

# Security and access information
output "function_allows_unauthenticated" {
  description = "Whether the function allows unauthenticated invocations"
  value       = var.allow_unauthenticated_invocations
}

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value       = var.enable_required_apis ? var.required_apis : []
}

# Resource naming information
output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

output "random_suffix" {
  description = "Random suffix used for resource uniqueness"
  value       = random_id.suffix.hex
}

# Applied labels
output "resource_labels" {
  description = "Labels applied to all resources"
  value       = local.common_labels
}

# Validation and testing endpoints
output "validation_endpoints" {
  description = "Information about form validation endpoints and expected responses"
  value = {
    url = google_cloudfunctions2_function.form_validation_function.service_config[0].uri
    methods = ["POST", "OPTIONS"]
    content_type = "application/json"
    cors_enabled = true
    expected_fields = {
      required = ["name", "email", "message"]
      optional = ["phone"]
    }
    response_format = {
      success = {
        success = true
        message = "Form submitted successfully"
        id = "document_id"
      }
      error = {
        success = false
        errors = ["Array of validation error messages"]
      }
    }
  }
}