# Function information outputs
output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.unit_converter.name
}

output "function_id" {
  description = "Fully qualified resource ID of the Cloud Function"
  value       = google_cloudfunctions2_function.unit_converter.id
}

output "function_url" {
  description = "HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.unit_converter.service_config[0].uri
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.unit_converter.location
}

output "function_runtime" {
  description = "Runtime used by the Cloud Function"
  value       = google_cloudfunctions2_function.unit_converter.build_config[0].runtime
}

# Function configuration outputs
output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = google_cloudfunctions2_function.unit_converter.service_config[0].available_memory
}

output "function_timeout" {
  description = "Timeout configuration for the Cloud Function"
  value       = google_cloudfunctions2_function.unit_converter.service_config[0].timeout_seconds
}

output "max_instances" {
  description = "Maximum number of function instances"
  value       = google_cloudfunctions2_function.unit_converter.service_config[0].max_instance_count
}

output "min_instances" {
  description = "Minimum number of function instances"
  value       = google_cloudfunctions2_function.unit_converter.service_config[0].min_instance_count
}

# Storage and build outputs
output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source"
  value       = google_storage_bucket.function_source_bucket.name
}

output "source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source"
  value       = google_storage_bucket.function_source_bucket.url
}

output "source_object_name" {
  description = "Name of the source code object in Cloud Storage"
  value       = google_storage_bucket_object.function_source_zip.name
}

# Security and access outputs
output "public_access_enabled" {
  description = "Whether unauthenticated access is enabled"
  value       = var.allow_unauthenticated
}

output "service_account_email" {
  description = "Service account email used by the Cloud Function"
  value       = google_cloudfunctions2_function.unit_converter.service_config[0].service_account_email
}

# API endpoints and testing information
output "api_examples" {
  description = "Example API calls for testing the unit converter"
  value = {
    temperature_get = "curl '${google_cloudfunctions2_function.unit_converter.service_config[0].uri}?category=temperature&type=celsius_to_fahrenheit&value=25'"
    temperature_post = jsonencode({
      curl_command = "curl -X POST '${google_cloudfunctions2_function.unit_converter.service_config[0].uri}' -H 'Content-Type: application/json' -d"
      json_body = {
        category = "temperature"
        type     = "fahrenheit_to_celsius" 
        value    = 77
      }
    })
    distance_conversion = jsonencode({
      curl_command = "curl -X POST '${google_cloudfunctions2_function.unit_converter.service_config[0].uri}' -H 'Content-Type: application/json' -d"
      json_body = {
        category = "distance"
        type     = "meters_to_feet"
        value    = 100
      }
    })
    weight_conversion = jsonencode({
      curl_command = "curl -X POST '${google_cloudfunctions2_function.unit_converter.service_config[0].uri}' -H 'Content-Type: application/json' -d"
      json_body = {
        category = "weight"
        type     = "kilograms_to_pounds"
        value    = 70
      }
    })
  }
}

# Available conversion types
output "supported_conversions" {
  description = "Supported conversion categories and types"
  value = {
    temperature = [
      "celsius_to_fahrenheit",
      "fahrenheit_to_celsius", 
      "celsius_to_kelvin",
      "kelvin_to_celsius",
      "fahrenheit_to_kelvin",
      "kelvin_to_fahrenheit"
    ]
    distance = [
      "meters_to_feet",
      "feet_to_meters",
      "kilometers_to_miles", 
      "miles_to_kilometers",
      "inches_to_centimeters",
      "centimeters_to_inches"
    ]
    weight = [
      "kilograms_to_pounds",
      "pounds_to_kilograms",
      "grams_to_ounces",
      "ounces_to_grams", 
      "tons_to_pounds",
      "pounds_to_tons"
    ]
  }
}

# Monitoring and logging information
output "monitoring_links" {
  description = "Links to monitoring and logging resources"
  value = {
    cloud_console_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.unit_converter.name}?project=${var.project_id}"
    cloud_logging          = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions2_function.unit_converter.name}%22?project=${var.project_id}"
    cloud_monitoring       = "https://console.cloud.google.com/monitoring/dashboards/resourceDetail/cloudfunctions_function/${google_cloudfunctions2_function.unit_converter.name}?project=${var.project_id}"
  }
}

# Resource identifiers for cleanup
output "resource_ids" {
  description = "Resource identifiers for management and cleanup"
  value = {
    function_id     = google_cloudfunctions2_function.unit_converter.id
    bucket_name     = google_storage_bucket.function_source_bucket.name
    random_suffix   = random_id.suffix.hex
    project_id      = var.project_id
    region          = var.region
  }
}