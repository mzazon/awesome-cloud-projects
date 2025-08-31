# Output values for Educational Content Generation Infrastructure
# These outputs provide important information for integrating with the deployed resources

output "function_url" {
  description = "URL of the deployed Cloud Function for content generation"
  value       = google_cloudfunctions2_function.content_generator.service_config[0].uri
  sensitive   = false
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.content_generator.name
  sensitive   = false
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_service_account.email
  sensitive   = false
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for audio files"
  value       = google_storage_bucket.audio_content_bucket.name
  sensitive   = false
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket for audio files"
  value       = google_storage_bucket.audio_content_bucket.url
  sensitive   = false
}

output "firestore_database_name" {
  description = "Name of the Firestore database for content storage"
  value       = google_firestore_database.educational_content_db.name
  sensitive   = false
}

output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
  sensitive   = false
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
  sensitive   = false
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
  sensitive   = false
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
  sensitive   = false
}

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value       = local.required_apis
  sensitive   = false
}

output "sample_curl_command" {
  description = "Sample curl command to test the content generation function"
  value = <<-EOT
    curl -X POST "${google_cloudfunctions2_function.content_generator.service_config[0].uri}" \
      -H "Content-Type: application/json" \
      -d '{
        "topic": "Introduction to Climate Science",
        "outline": "1. What is climate vs weather? 2. Greenhouse effect basics 3. Human impact on climate 4. Climate change evidence 5. Mitigation strategies",
        "voice_name": "en-US-Studio-M"
      }'
  EOT
  sensitive   = false
}

output "firestore_collection_name" {
  description = "Firestore collection name for educational content storage"
  value       = "educational_content"
  sensitive   = false
}

output "audio_storage_path" {
  description = "Cloud Storage path pattern for generated audio files"
  value       = "gs://${google_storage_bucket.audio_content_bucket.name}/lessons/"
  sensitive   = false
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
  sensitive   = false
}

output "deployment_summary" {
  description = "Summary of deployed resources for the educational content generation system"
  value = {
    function = {
      name        = google_cloudfunctions2_function.content_generator.name
      url         = google_cloudfunctions2_function.content_generator.service_config[0].uri
      memory      = "1Gi"
      timeout     = "540s"
      runtime     = "python311"
      trigger     = "HTTP"
    }
    storage = {
      bucket_name    = google_storage_bucket.audio_content_bucket.name
      storage_class  = "STANDARD"
      versioning    = true
      public_access  = true
      lifecycle_rule = "Move to Nearline after 365 days"
    }
    database = {
      type       = "Firestore Native"
      location   = var.region
      collection = "educational_content"
    }
    ai_services = {
      vertex_ai_model = "gemini-2.5-flash"
      tts_voices     = "en-US Studio voices and 380+ others"
      features       = ["Content Generation", "Audio Synthesis", "Real-time Storage"]
    }
  }
  sensitive = false
}

output "monitoring_and_logging" {
  description = "Information about monitoring and logging for the deployment"
  value = {
    function_logs_command = "gcloud functions logs read ${google_cloudfunctions2_function.content_generator.name} --region=${var.region}"
    storage_metrics      = "Available in Cloud Monitoring under Cloud Storage metrics"
    firestore_monitoring = "Available in Cloud Monitoring under Firestore metrics"
    vertex_ai_usage     = "Available in Cloud Monitoring under Vertex AI metrics"
  }
  sensitive = false
}

output "cost_optimization_tips" {
  description = "Cost optimization recommendations for the educational content generation system"
  value = {
    function_scaling = "Function scales to zero when not in use - pay only for actual usage"
    storage_lifecycle = "Audio files automatically moved to cheaper Nearline storage after 365 days"
    vertex_ai_model = "Gemini 2.5 Flash selected for optimal price-performance ratio"
    firestore_reads = "Use efficient queries and caching to minimize Firestore read costs"
    tts_optimization = "Batch multiple content pieces to optimize Text-to-Speech API calls"
  }
  sensitive = false
}

output "security_configuration" {
  description = "Security configuration details for the deployment"
  value = {
    service_account = {
      email       = google_service_account.function_service_account.email
      permissions = ["Vertex AI User", "Text-to-Speech Developer", "Firestore User", "Storage Object Admin"]
    }
    iam_bindings = {
      function_invoker = "allUsers (public access for educational content)"
      storage_viewer   = "allUsers (public read access for audio files)"
    }
    api_access = {
      vertex_ai       = "Enabled with least privilege access"
      text_to_speech  = "Enabled with developer role"
      firestore      = "Enabled with user role"
      cloud_storage  = "Enabled with object admin role for bucket"
    }
  }
  sensitive = false
}

output "integration_endpoints" {
  description = "API endpoints and integration information"
  value = {
    content_generation_endpoint = google_cloudfunctions2_function.content_generator.service_config[0].uri
    expected_request_format = {
      topic      = "string (required) - The educational topic title"
      outline    = "string (required) - Curriculum outline or learning objectives"
      voice_name = "string (optional) - Text-to-Speech voice name (default: en-US-Studio-M)"
    }
    expected_response_format = {
      status           = "string - 'success' or 'error'"
      document_id      = "string - Firestore document ID for the generated content"
      content_preview  = "string - First 200 characters of generated content"
      audio_url        = "string - Cloud Storage URL for the generated audio file"
    }
  }
  sensitive = false
}