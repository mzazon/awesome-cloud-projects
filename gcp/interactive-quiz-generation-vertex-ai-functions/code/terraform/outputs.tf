# Output values for the Interactive Quiz Generation system
# These outputs provide essential information for using and managing the deployed infrastructure

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "bucket_name" {
  description = "Name of the Cloud Storage bucket for learning materials"
  value       = google_storage_bucket.quiz_materials.name
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket for learning materials"
  value       = google_storage_bucket.quiz_materials.url
}

output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "service_account_email" {
  description = "Email of the service account used for AI and storage operations"
  value       = google_service_account.quiz_ai_service.email
}

# Quiz Generator Function Outputs
output "quiz_generator_function_name" {
  description = "Name of the quiz generator Cloud Function"
  value       = google_cloudfunctions_function.quiz_generator.name
}

output "quiz_generator_function_url" {
  description = "HTTP trigger URL for the quiz generator function"
  value       = google_cloudfunctions_function.quiz_generator.https_trigger_url
}

output "quiz_generator_function_status" {
  description = "Status of the quiz generator function"
  value       = google_cloudfunctions_function.quiz_generator.status
}

# Quiz Delivery Function Outputs
output "quiz_delivery_function_name" {
  description = "Name of the quiz delivery Cloud Function"
  value       = google_cloudfunctions_function.quiz_delivery.name
}

output "quiz_delivery_function_url" {
  description = "HTTP trigger URL for the quiz delivery function"
  value       = google_cloudfunctions_function.quiz_delivery.https_trigger_url
}

output "quiz_delivery_function_status" {
  description = "Status of the quiz delivery function"
  value       = google_cloudfunctions_function.quiz_delivery.status
}

# Quiz Scoring Function Outputs
output "quiz_scoring_function_name" {
  description = "Name of the quiz scoring Cloud Function"
  value       = google_cloudfunctions_function.quiz_scoring.name
}

output "quiz_scoring_function_url" {
  description = "HTTP trigger URL for the quiz scoring function"
  value       = google_cloudfunctions_function.quiz_scoring.https_trigger_url
}

output "quiz_scoring_function_status" {
  description = "Status of the quiz scoring function"
  value       = google_cloudfunctions_function.quiz_scoring.status
}

# API Endpoints for easy reference
output "api_endpoints" {
  description = "Complete API endpoints for the quiz generation system"
  value = {
    generator = google_cloudfunctions_function.quiz_generator.https_trigger_url
    delivery  = google_cloudfunctions_function.quiz_delivery.https_trigger_url
    scoring   = google_cloudfunctions_function.quiz_scoring.https_trigger_url
  }
}

# Storage structure information
output "storage_structure" {
  description = "Information about the Cloud Storage bucket structure"
  value = {
    bucket_name = google_storage_bucket.quiz_materials.name
    folders = {
      uploads = "uploads/"
      quizzes = "quizzes/"
      results = "results/"
    }
    bucket_location    = google_storage_bucket.quiz_materials.location
    storage_class      = google_storage_bucket.quiz_materials.storage_class
    versioning_enabled = google_storage_bucket.quiz_materials.versioning[0].enabled
  }
}

# Resource names for reference
output "resource_names" {
  description = "Names of all created resources for reference"
  value = {
    storage_bucket         = google_storage_bucket.quiz_materials.name
    function_source_bucket = google_storage_bucket.function_source.name
    service_account       = google_service_account.quiz_ai_service.account_id
    generator_function    = google_cloudfunctions_function.quiz_generator.name
    delivery_function     = google_cloudfunctions_function.quiz_delivery.name
    scoring_function      = google_cloudfunctions_function.quiz_scoring.name
  }
}

# Configuration summary
output "configuration_summary" {
  description = "Summary of key configuration values used in deployment"
  value = {
    environment           = var.environment
    resource_prefix       = var.resource_prefix
    function_timeout      = var.function_timeout
    function_memory       = var.function_memory
    vertex_ai_location    = var.vertex_ai_location
    lifecycle_enabled     = var.enable_lifecycle_policy
    versioning_enabled    = var.enable_versioning
    uniform_bucket_access = var.enable_uniform_bucket_access
  }
}

# Quick start commands
output "quick_start_commands" {
  description = "Useful commands for testing the deployed system"
  value = {
    test_generator = "curl -X POST ${google_cloudfunctions_function.quiz_generator.https_trigger_url} -H 'Content-Type: application/json' -d '{\"content\":\"Sample educational content\",\"question_count\":3,\"difficulty\":\"medium\"}'"
    test_delivery  = "curl '${google_cloudfunctions_function.quiz_delivery.https_trigger_url}?quiz_id=QUIZ_ID_HERE'"
    test_scoring   = "curl -X POST ${google_cloudfunctions_function.quiz_scoring.https_trigger_url} -H 'Content-Type: application/json' -d '{\"quiz_id\":\"QUIZ_ID\",\"answers\":{\"0\":1,\"1\":true},\"student_id\":\"test_student\"}'"
    list_quizzes   = "gsutil ls gs://${google_storage_bucket.quiz_materials.name}/quizzes/"
    list_results   = "gsutil ls gs://${google_storage_bucket.quiz_materials.name}/results/"
  }
}

# Cost estimation information
output "cost_information" {
  description = "Information about potential costs and optimization"
  value = {
    estimated_monthly_cost = "Estimated $10-50/month for moderate usage (depends on Vertex AI token consumption)"
    cost_factors = [
      "Vertex AI Gemini model usage (primary cost driver)",
      "Cloud Functions invocations and execution time",
      "Cloud Storage bucket usage and operations",
      "Data transfer costs"
    ]
    cost_optimization_tips = [
      "Use lifecycle policies to reduce storage costs",
      "Monitor and optimize function memory allocation",
      "Implement caching for frequently accessed quizzes",
      "Set appropriate function timeouts to avoid unnecessary charges"
    ]
  }
}

# Security considerations
output "security_notes" {
  description = "Important security considerations for the deployed system"
  value = {
    current_setup = "Functions are publicly accessible for educational demonstration"
    production_recommendations = [
      "Implement proper authentication (IAM, OAuth, or API keys)",
      "Enable Cloud Armor for DDoS protection",
      "Use VPC Service Controls for additional network security",
      "Implement request rate limiting",
      "Enable audit logging for all function calls",
      "Use Cloud KMS for sensitive data encryption"
    ]
    data_privacy = "Ensure compliance with educational data privacy regulations (FERPA, COPPA, GDPR)"
  }
}