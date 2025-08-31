# Output values for the Word Count API infrastructure
# These outputs provide important information about the deployed resources
# for verification, testing, and integration with other systems

output "function_url" {
  description = "HTTP URL for the deployed Cloud Function API endpoint"
  value       = google_cloudfunctions2_function.word_count_api.service_config[0].uri
  sensitive   = false
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.word_count_api.name
  sensitive   = false
}

output "function_location" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.word_count_api.location
  sensitive   = false
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for file processing"
  value       = google_storage_bucket.word_count_files.name
  sensitive   = false
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.word_count_files.url
  sensitive   = false
}

output "function_service_account" {
  description = "Email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
  sensitive   = false
}

output "project_id" {
  description = "Google Cloud Project ID where resources were created"
  value       = var.project_id
  sensitive   = false
}

output "region" {
  description = "Google Cloud region where resources were deployed"
  value       = var.region
  sensitive   = false
}

# API testing information
output "api_test_commands" {
  description = "Sample commands for testing the deployed API"
  value = {
    health_check = "curl -X GET '${google_cloudfunctions2_function.word_count_api.service_config[0].uri}'"
    direct_text_analysis = "curl -X POST '${google_cloudfunctions2_function.word_count_api.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"text\": \"Hello world! This is a sample text for word counting.\"}'"
    file_analysis = "curl -X POST '${google_cloudfunctions2_function.word_count_api.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"bucket_name\": \"${google_storage_bucket.word_count_files.name}\", \"file_path\": \"sample.txt\"}'"
  }
  sensitive = false
}

# Resource information for monitoring and management
output "function_resource_info" {
  description = "Detailed information about the Cloud Function configuration"
  value = {
    memory        = var.function_memory
    timeout       = var.function_timeout
    max_instances = var.max_instances
    min_instances = var.min_instances
    runtime       = "python312"
    entry_point   = "word_count_api"
  }
  sensitive = false
}

output "storage_info" {
  description = "Information about the Cloud Storage bucket configuration"
  value = {
    name                        = google_storage_bucket.word_count_files.name
    location                    = google_storage_bucket.word_count_files.location
    storage_class              = google_storage_bucket.word_count_files.storage_class
    uniform_bucket_level_access = google_storage_bucket.word_count_files.uniform_bucket_level_access
    public_access_prevention   = google_storage_bucket.word_count_files.public_access_prevention
  }
  sensitive = false
}

# IAM and security information
output "security_info" {
  description = "Security and IAM configuration details"
  value = {
    function_service_account   = google_service_account.function_sa.email
    public_access_enabled     = var.enable_public_access
    storage_access_role       = "roles/storage.objectViewer"
    uniform_bucket_access     = true
    public_access_prevention  = "enforced"
  }
  sensitive = false
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources (approximate)"
  value = {
    function_invocations_free_tier = "2,000,000 invocations/month"
    storage_free_tier             = "5 GB/month"
    estimated_monthly_cost        = "$0.00 - $2.00 (within free tier limits)"
    cost_factors = [
      "Function invocations beyond 2M/month",
      "Function compute time beyond 400K GB-seconds/month",
      "Storage beyond 5 GB/month",
      "Network egress charges"
    ]
  }
  sensitive = false
}

# Deployment verification URLs and commands
output "verification_steps" {
  description = "Commands to verify the deployment is working correctly"
  value = {
    step_1_health_check = {
      command     = "curl -X GET '${google_cloudfunctions2_function.word_count_api.service_config[0].uri}'"
      description = "Verify the function is responding to health checks"
      expected    = "JSON response with API information"
    }
    step_2_word_count_test = {
      command     = "curl -X POST '${google_cloudfunctions2_function.word_count_api.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"text\": \"one two three four five\"}'"
      description = "Test word counting with known input"
      expected    = "JSON response with word_count: 5"
    }
    step_3_function_logs = {
      command     = "gcloud functions logs read ${google_cloudfunctions2_function.word_count_api.name} --gen2 --limit=10"
      description = "Check function execution logs"
      expected    = "Recent log entries showing function execution"
    }
  }
  sensitive = false
}