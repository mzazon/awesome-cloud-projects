# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ==============================================================================
# FUNCTION URLS AND ENDPOINTS
# ==============================================================================

output "encoder_function_url" {
  description = "HTTPS URL of the Base64 encoder function"
  value       = google_cloudfunctions2_function.encoder.service_config[0].uri
  sensitive   = false
}

output "decoder_function_url" {
  description = "HTTPS URL of the Base64 decoder function"
  value       = google_cloudfunctions2_function.decoder.service_config[0].uri
  sensitive   = false
}

output "encoder_function_id" {
  description = "Fully qualified resource ID of the encoder function"
  value       = google_cloudfunctions2_function.encoder.id
}

output "decoder_function_id" {
  description = "Fully qualified resource ID of the decoder function"
  value       = google_cloudfunctions2_function.decoder.id
}

# ==============================================================================
# FUNCTION METADATA
# ==============================================================================

output "encoder_function_name" {
  description = "Name of the Base64 encoder function"
  value       = google_cloudfunctions2_function.encoder.name
}

output "decoder_function_name" {
  description = "Name of the Base64 decoder function"
  value       = google_cloudfunctions2_function.decoder.name
}

output "functions_region" {
  description = "Google Cloud region where functions are deployed"
  value       = var.region
}

output "functions_runtime" {
  description = "Runtime version used for the functions"
  value       = var.function_runtime
}

# ==============================================================================
# STORAGE INFORMATION
# ==============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for file operations"
  value       = google_storage_bucket.function_bucket.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_bucket.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.function_bucket.self_link
}

# ==============================================================================
# TESTING AND USAGE EXAMPLES
# ==============================================================================

output "curl_examples" {
  description = "Example curl commands for testing the functions"
  value = {
    encoder_get = "curl '${google_cloudfunctions2_function.encoder.service_config[0].uri}?text=Hello%20World'"
    encoder_post_json = jsonencode({
      command = "curl -X POST '${google_cloudfunctions2_function.encoder.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"text\":\"Hello World\"}'"
    })
    encoder_post_file = "curl -X POST '${google_cloudfunctions2_function.encoder.service_config[0].uri}' -F 'file=@example.txt'"
    decoder_get = "curl '${google_cloudfunctions2_function.decoder.service_config[0].uri}?encoded=SGVsbG8gV29ybGQ%3D'"
    decoder_post = jsonencode({
      command = "curl -X POST '${google_cloudfunctions2_function.decoder.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"encoded\":\"SGVsbG8gV29ybGQ=\"}'"
    })
  }
}

# ==============================================================================
# SECURITY AND ACCESS INFORMATION
# ==============================================================================

output "public_access_enabled" {
  description = "Whether public access is enabled for the functions"
  value       = var.enable_public_access
}

output "cors_origins" {
  description = "Configured CORS origins for the functions"
  value       = var.cors_origins
}

# ==============================================================================
# RESOURCE MANAGEMENT
# ==============================================================================

output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "resource_labels" {
  description = "Labels applied to all resources"
  value       = local.common_labels
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# ==============================================================================
# COST OPTIMIZATION INFORMATION
# ==============================================================================

output "function_scaling_config" {
  description = "Function scaling configuration for cost optimization"
  value = {
    min_instances = var.min_instances
    max_instances = var.max_instances
    memory        = var.function_memory
    timeout       = var.function_timeout
  }
}

output "storage_configuration" {
  description = "Storage configuration for cost optimization"
  value = {
    storage_class    = var.storage_class
    location         = var.storage_location
    lifecycle_enabled = var.enable_lifecycle
    lifecycle_age    = var.enable_lifecycle ? var.lifecycle_age_days : null
    versioning       = var.enable_versioning
  }
}

# ==============================================================================
# OPERATIONAL INFORMATION
# ==============================================================================

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "run.googleapis.com"
  ]
}

output "monitoring_links" {
  description = "Links to monitoring and logging dashboards"
  value = {
    encoder_logs = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.encoder.name}?project=${var.project_id}&subtab=logs"
    decoder_logs = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.decoder.name}?project=${var.project_id}&subtab=logs"
    storage_console = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.function_bucket.name}?project=${var.project_id}"
  }
}

# ==============================================================================
# QUICK START GUIDE
# ==============================================================================

output "quick_start_guide" {
  description = "Quick start guide for using the deployed functions"
  value = {
    description = "Base64 Encoder/Decoder Functions - Quick Start"
    encoder_url = google_cloudfunctions2_function.encoder.service_config[0].uri
    decoder_url = google_cloudfunctions2_function.decoder.service_config[0].uri
    examples = {
      encode_text = {
        method = "GET"
        url = "${google_cloudfunctions2_function.encoder.service_config[0].uri}?text=Hello%20World"
        description = "Encode text via GET request"
      }
      decode_text = {
        method = "GET" 
        url = "${google_cloudfunctions2_function.decoder.service_config[0].uri}?encoded=SGVsbG8gV29ybGQ%3D"
        description = "Decode Base64 text via GET request"
      }
      encode_json = {
        method = "POST"
        url = google_cloudfunctions2_function.encoder.service_config[0].uri
        body = "{\"text\":\"Hello World\"}"
        headers = {"Content-Type" = "application/json"}
        description = "Encode text via POST JSON"
      }
      upload_file = {
        method = "POST"
        url = google_cloudfunctions2_function.encoder.service_config[0].uri
        body = "form-data with 'file' field"
        description = "Encode file via POST form upload"
      }
    }
    notes = [
      "All functions support CORS for browser-based applications",
      "Functions automatically scale based on demand",
      "Both text and binary data are supported",
      "File uploads are supported via form data",
      "Functions include comprehensive error handling and validation"
    ]
  }
}