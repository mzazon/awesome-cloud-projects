# Output values for GCP Text Case Converter API infrastructure

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.text_case_converter.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.text_case_converter.url
}

output "function_uri" {
  description = "URI of the deployed Cloud Function service"
  value       = google_cloudfunctions2_function.text_case_converter.service_config[0].uri
}

output "function_id" {
  description = "Fully qualified function ID"
  value       = google_cloudfunctions2_function.text_case_converter.id
}

output "function_location" {
  description = "Location where the function is deployed"
  value       = google_cloudfunctions2_function.text_case_converter.location
}

output "function_state" {
  description = "Current state of the Cloud Function"
  value       = google_cloudfunctions2_function.text_case_converter.state
}

output "function_update_time" {
  description = "Last update timestamp of the Cloud Function"
  value       = google_cloudfunctions2_function.text_case_converter.update_time
}

output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source"
  value       = google_storage_bucket.function_source_bucket.name
}

output "source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source"
  value       = google_storage_bucket.function_source_bucket.url
}

output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "GCP region where resources are deployed"
  value       = var.region
}

output "curl_test_command" {
  description = "Example curl command to test the deployed function"
  value = format(
    "curl -X POST %s -H 'Content-Type: application/json' -d '{\"text\": \"hello world\", \"case_type\": \"upper\"}'",
    google_cloudfunctions2_function.text_case_converter.url
  )
}

output "function_logs_command" {
  description = "gcloud command to view function logs"
  value = format(
    "gcloud functions logs read %s --region=%s --limit=50",
    google_cloudfunctions2_function.text_case_converter.name,
    var.region
  )
}

output "effective_labels" {
  description = "All labels present on the function resource"
  value       = google_cloudfunctions2_function.text_case_converter.effective_labels
}

output "api_endpoints" {
  description = "Available API endpoints and their descriptions"
  value = {
    convert = {
      url    = google_cloudfunctions2_function.text_case_converter.url
      method = "POST"
      description = "Convert text between different case formats"
      example_payload = {
        text      = "Hello World Example"
        case_type = "camel"
      }
      supported_case_types = [
        "upper", "uppercase",
        "lower", "lowercase", 
        "title", "titlecase",
        "capitalize",
        "camel", "camelcase",
        "pascal", "pascalcase",
        "snake", "snakecase",
        "kebab", "kebabcase"
      ]
    }
  }
}