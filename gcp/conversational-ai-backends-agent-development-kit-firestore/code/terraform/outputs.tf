# Outputs for Conversational AI Backend Infrastructure
# These outputs provide essential information for accessing and managing the deployed resources

# Project and deployment information
output "project_id" {
  description = "The Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for resource naming"
  value       = random_id.suffix.hex
}

# Cloud Functions endpoints and information
output "chat_processor_url" {
  description = "HTTP endpoint URL for the main conversation processing function"
  value       = google_cloudfunctions2_function.chat_processor.service_config[0].uri
  sensitive   = false
}

output "chat_history_url" {
  description = "HTTP endpoint URL for conversation history retrieval function"
  value       = google_cloudfunctions2_function.chat_history.service_config[0].uri
  sensitive   = false
}

output "chat_processor_name" {
  description = "Name of the main conversation processing Cloud Function"
  value       = google_cloudfunctions2_function.chat_processor.name
}

output "chat_history_name" {
  description = "Name of the conversation history Cloud Function"
  value       = google_cloudfunctions2_function.chat_history.name
}

# Firestore database information
output "firestore_database_name" {
  description = "Name of the Firestore database for conversation storage"
  value       = google_firestore_database.conversation_db.name
}

output "firestore_database_id" {
  description = "Full database ID for Firestore access"
  value       = google_firestore_database.conversation_db.name
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.conversation_db.location_id
}

# Cloud Storage bucket information
output "conversation_bucket_name" {
  description = "Name of the Cloud Storage bucket for conversation artifacts"
  value       = google_storage_bucket.conversation_artifacts.name
}

output "conversation_bucket_url" {
  description = "URL of the Cloud Storage bucket for conversation artifacts"
  value       = google_storage_bucket.conversation_artifacts.url
}

output "conversation_bucket_self_link" {
  description = "Self-link of the conversation artifacts bucket"
  value       = google_storage_bucket.conversation_artifacts.self_link
}

# Service account information
output "function_service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.email
}

output "function_service_account_id" {
  description = "Unique ID of the service account used by Cloud Functions"
  value       = google_service_account.function_service_account.unique_id
}

# Secret Manager information
output "ai_config_secret_name" {
  description = "Name of the Secret Manager secret containing AI configuration"
  value       = google_secret_manager_secret.ai_config.secret_id
}

output "ai_config_secret_id" {
  description = "Full resource ID of the AI configuration secret"
  value       = google_secret_manager_secret.ai_config.id
}

# Monitoring and observability
output "monitoring_dashboard_url" {
  description = "URL to access the Cloud Monitoring dashboard (if enabled)"
  value = var.enable_monitoring ? (
    "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.conversation_ai_dashboard[0].id}?project=${var.project_id}"
  ) : "Monitoring dashboard not enabled"
}

output "function_logs_url" {
  description = "URL to view Cloud Function logs in the Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

# API testing information
output "api_testing_examples" {
  description = "Example curl commands for testing the API endpoints"
  value = {
    chat_processor = "curl -X POST ${google_cloudfunctions2_function.chat_processor.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"user_id\": \"test_user\", \"message\": \"Hello, can you help me?\", \"session_id\": \"test_session\"}'"
    chat_history   = "curl -X GET '${google_cloudfunctions2_function.chat_history.service_config[0].uri}?user_id=test_user'"
  }
}

# Resource naming information
output "resource_names" {
  description = "Map of all created resource names for reference"
  value = {
    project_name           = local.project_name
    function_name         = local.function_name
    history_function_name = local.history_function_name
    bucket_name          = local.bucket_name
    firestore_database   = local.firestore_database
    service_account_name = google_service_account.function_service_account.name
    secret_name          = google_secret_manager_secret.ai_config.secret_id
  }
}

# Security and access information
output "public_endpoints" {
  description = "List of public endpoints that require security consideration"
  value = [
    google_cloudfunctions2_function.chat_processor.service_config[0].uri,
    google_cloudfunctions2_function.chat_history.service_config[0].uri
  ]
}

output "iam_roles_assigned" {
  description = "List of IAM roles assigned to the service account"
  value = [
    "roles/datastore.user",
    "roles/storage.objectAdmin", 
    "roles/aiplatform.user",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/secretmanager.secretAccessor"
  ]
}

# Vertex AI configuration
output "vertex_ai_region" {
  description = "Region configured for Vertex AI services"
  value       = local.vertex_ai_region
}

# Environment and configuration
output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Cost optimization information
output "cost_optimization_notes" {
  description = "Important notes for cost optimization"
  value = {
    bucket_lifecycle_age    = "${var.bucket_lifecycle_age} days"
    function_min_instances  = var.min_instances
    function_max_instances  = var.max_instances
    storage_class          = var.storage_class
    conversation_retention = "${var.conversation_retention_days} days"
  }
}

# Quick start commands
output "quick_start_commands" {
  description = "Commands to get started with the deployed infrastructure"
  value = {
    test_chat_endpoint = "curl -X POST ${google_cloudfunctions2_function.chat_processor.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"user_id\": \"demo_user\", \"message\": \"Hello! Can you help me get started?\"}'"
    view_firestore     = "gcloud firestore databases describe ${google_firestore_database.conversation_db.name} --project=${var.project_id}"
    list_conversations = "gcloud firestore query --collection-group=conversations --limit=10 --project=${var.project_id}"
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.chat_processor.name} --region=${var.region} --project=${var.project_id}"
  }
}

# Health check endpoints
output "health_check_urls" {
  description = "URLs for monitoring the health of the deployed services"
  value = {
    chat_processor_health = "${google_cloudfunctions2_function.chat_processor.service_config[0].uri}/health"
    chat_history_health   = "${google_cloudfunctions2_function.chat_history.service_config[0].uri}/health"
  }
}

# Documentation and next steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Test the API endpoints using the provided curl commands",
    "Configure monitoring alerts with your actual email address",
    "Review and adjust security settings for production use",
    "Set up CI/CD pipelines for function updates",
    "Configure custom domain names for the API endpoints",
    "Implement rate limiting and API authentication",
    "Review and optimize function memory and timeout settings",
    "Set up backup strategies for Firestore data"
  ]
}