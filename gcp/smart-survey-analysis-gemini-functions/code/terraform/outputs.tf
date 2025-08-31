# Outputs for Smart Survey Analysis Infrastructure
# These outputs provide essential information for testing and integration

output "project_id" {
  description = "The Google Cloud Project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

# Cloud Function Outputs
output "function_name" {
  description = "The deployed Cloud Function name"
  value       = google_cloudfunctions2_function.survey_analyzer.name
}

output "function_url" {
  description = "The HTTP trigger URL for the survey analysis function"
  value       = google_cloudfunctions2_function.survey_analyzer.service_config[0].uri
  sensitive   = false
}

output "function_location" {
  description = "The location where the Cloud Function was deployed"
  value       = google_cloudfunctions2_function.survey_analyzer.location
}

output "function_service_account" {
  description = "The service account email used by the Cloud Function"
  value       = google_service_account.function_service_account.email
}

# Firestore Database Outputs
output "firestore_database_name" {
  description = "The name of the Firestore database for survey data"
  value       = google_firestore_database.survey_database.name
}

output "firestore_database_location" {
  description = "The location of the Firestore database"
  value       = google_firestore_database.survey_database.location_id
}

output "firestore_database_type" {
  description = "The type of Firestore database (FIRESTORE_NATIVE)"
  value       = google_firestore_database.survey_database.type
}

# Storage Outputs
output "function_source_bucket" {
  description = "The Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "The Cloud Storage bucket URL for function source code"
  value       = google_storage_bucket.function_source.url
}

# AI/ML Configuration Outputs
output "gemini_model" {
  description = "The Vertex AI Gemini model used for survey analysis"
  value       = var.gemini_model
}

output "vertex_ai_region" {
  description = "The region where Vertex AI services are accessed"
  value       = var.region
}

# Security and Access Outputs
output "public_access_enabled" {
  description = "Whether public access to the Cloud Function is enabled"
  value       = var.enable_public_access
}

output "ingress_settings" {
  description = "The ingress settings for the Cloud Function"
  value       = var.ingress_settings
}

# Monitoring Outputs
output "monitoring_enabled" {
  description = "Whether Cloud Monitoring alerts are enabled"
  value       = var.enable_monitoring
}

output "error_rate_alert_policy" {
  description = "The Cloud Monitoring alert policy for function error rate"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_error_rate[0].name : null
}

output "latency_alert_policy" {
  description = "The Cloud Monitoring alert policy for function latency"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_latency[0].name : null
}

# Resource Configuration Outputs
output "function_memory" {
  description = "The memory allocation for the Cloud Function (MB)"
  value       = var.function_memory
}

output "function_timeout" {
  description = "The timeout for the Cloud Function (seconds)"
  value       = var.function_timeout
}

output "function_runtime" {
  description = "The runtime version for the Cloud Function"
  value       = var.function_runtime
}

output "max_instances" {
  description = "The maximum number of function instances"
  value       = var.max_instances
}

output "min_instances" {
  description = "The minimum number of function instances"
  value       = var.min_instances
}

# Collection and Index Information
output "survey_collection_name" {
  description = "The Firestore collection name for survey analyses"
  value       = "survey_analyses"
}

output "firestore_index_name" {
  description = "The Firestore index for efficient survey data querying"
  value       = google_firestore_index.survey_analyses_index.name
}

# Useful URLs and Commands
output "console_urls" {
  description = "Useful Google Cloud Console URLs for monitoring and management"
  value = {
    cloud_functions = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.survey_analyzer.name}?project=${var.project_id}"
    firestore       = "https://console.cloud.google.com/firestore/databases/${google_firestore_database.survey_database.name}/data?project=${var.project_id}"
    vertex_ai       = "https://console.cloud.google.com/vertex-ai/workbench?project=${var.project_id}"
    monitoring      = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    logs            = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions2_function.survey_analyzer.name}%22?project=${var.project_id}"
  }
}

# Testing and Integration Information
output "test_curl_command" {
  description = "Example curl command to test the survey analysis function"
  value = <<-EOT
curl -X POST "${google_cloudfunctions2_function.survey_analyzer.service_config[0].uri}" \
  -H "Content-Type: application/json" \
  -d '{
    "survey_id": "test-survey-001",
    "responses": [
      {
        "question": "How satisfied are you with our service?",
        "answer": "Very satisfied! The service was excellent and exceeded my expectations."
      },
      {
        "question": "Any suggestions for improvement?",
        "answer": "Perhaps faster response times would be nice, but overall very good."
      }
    ]
  }'
EOT
}

output "python_client_example" {
  description = "Example Python code to interact with the survey analysis API"
  value = <<-EOT
import requests
import json

def analyze_survey(survey_data):
    url = "${google_cloudfunctions2_function.survey_analyzer.service_config[0].uri}"
    headers = {"Content-Type": "application/json"}
    
    response = requests.post(url, json=survey_data, headers=headers)
    
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"API call failed: {response.status_code} - {response.text}")

# Example usage
survey_data = {
    "survey_id": "customer-feedback-2024",
    "responses": [
        {
            "question": "Rate your experience",
            "answer": "Excellent service and support!"
        }
    ]
}

result = analyze_survey(survey_data)
print(json.dumps(result, indent=2))
EOT
}

# Resource Labels
output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Random suffix for uniqueness
output "deployment_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}