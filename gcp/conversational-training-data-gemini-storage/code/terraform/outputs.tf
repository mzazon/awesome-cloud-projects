# Project and Configuration Outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

# Storage Outputs
output "training_data_bucket_name" {
  description = "Name of the Cloud Storage bucket for training data"
  value       = google_storage_bucket.training_data.name
}

output "training_data_bucket_url" {
  description = "URL of the Cloud Storage bucket for training data"
  value       = google_storage_bucket.training_data.url
}

output "training_data_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.training_data.self_link
}

output "bucket_folders" {
  description = "List of organized folder structure in the bucket"
  value = [
    "raw-conversations/",
    "processed-conversations/",
    "formatted-training/",
    "templates/"
  ]
}

# Cloud Functions Outputs
output "conversation_generator_function_name" {
  description = "Name of the conversation generator Cloud Function"
  value       = google_cloudfunctions2_function.conversation_generator.name
}

output "conversation_generator_function_url" {
  description = "HTTP trigger URL for the conversation generator function"
  value       = google_cloudfunctions2_function.conversation_generator.service_config[0].uri
}

output "data_processor_function_name" {
  description = "Name of the data processor Cloud Function"
  value       = google_cloudfunctions2_function.data_processor.name
}

output "data_processor_function_url" {
  description = "HTTP trigger URL for the data processor function"
  value       = google_cloudfunctions2_function.data_processor.service_config[0].uri
}

# Service Account Outputs
output "generator_service_account_email" {
  description = "Email of the conversation generator service account"
  value       = var.create_service_accounts ? google_service_account.generator_function_sa[0].email : "Default Compute Service Account"
}

output "processor_service_account_email" {
  description = "Email of the data processor service account"
  value       = var.create_service_accounts ? google_service_account.processor_function_sa[0].email : "Default Compute Service Account"
}

# AI Configuration Outputs
output "vertex_ai_region" {
  description = "Region configured for Vertex AI services"
  value       = var.vertex_ai_region
}

output "gemini_model" {
  description = "Gemini model configured for conversation generation"
  value       = var.gemini_model
}

# Template Configuration Output
output "conversation_templates_location" {
  description = "Location of conversation templates in Cloud Storage"
  value       = "gs://${google_storage_bucket.training_data.name}/templates/conversation_templates.json"
}

output "conversation_scenarios" {
  description = "Available conversation scenarios for generation"
  value       = [for template in var.conversation_templates.templates : template.scenario]
}

# Monitoring Outputs
output "monitoring_enabled" {
  description = "Whether monitoring resources were created"
  value       = var.enable_monitoring
}

output "log_metrics_created" {
  description = "List of created log-based metrics"
  value = var.enable_monitoring ? [
    google_logging_metric.conversation_generation_success[0].name,
    google_logging_metric.conversation_generation_errors[0].name
  ] : []
}

output "log_sink_destination" {
  description = "Destination for conversation generation logs"
  value       = var.enable_monitoring ? "gs://${google_storage_bucket.training_data.name}/logs" : "Not configured"
}

# API Configuration Outputs
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = var.enable_apis
}

# Usage Examples and Commands
output "sample_generation_command" {
  description = "Sample curl command to generate conversations"
  value = <<-EOT
    curl -X POST "${google_cloudfunctions2_function.conversation_generator.service_config[0].uri}" \
      -H "Content-Type: application/json" \
      -d '{
        "num_conversations": 10,
        "scenario": "customer_support"
      }'
  EOT
}

output "sample_processing_command" {
  description = "Sample curl command to process conversations"
  value = <<-EOT
    curl -X POST "${google_cloudfunctions2_function.data_processor.service_config[0].uri}" \
      -H "Content-Type: application/json" \
      -d '{
        "bucket_name": "${google_storage_bucket.training_data.name}"
      }'
  EOT
}

# File Access Commands
output "bucket_list_command" {
  description = "Command to list all files in the training data bucket"
  value       = "gsutil ls -r gs://${google_storage_bucket.training_data.name}/"
}

output "download_formatted_data_command" {
  description = "Command to download formatted training data"
  value       = "gsutil cp gs://${google_storage_bucket.training_data.name}/formatted-training/* ."
}

output "view_templates_command" {
  description = "Command to view conversation templates"
  value       = "gsutil cat gs://${google_storage_bucket.training_data.name}/templates/conversation_templates.json"
}

# Cost Estimation Outputs
output "estimated_monthly_cost_breakdown" {
  description = "Estimated monthly costs for different usage levels (USD)"
  value = {
    storage_gb_per_month = "~$0.02 per GB stored"
    cloud_functions = "First 2M invocations free, then $0.40 per million"
    vertex_ai_gemini = "Input: $0.000125 per 1K chars, Output: $0.000375 per 1K chars"
    monitoring_logs = "First 50 GB free, then $0.50 per GB"
  }
}

# Security and Access Information
output "bucket_access_control" {
  description = "Bucket access control configuration"
  value = {
    uniform_bucket_level_access = true
    versioning_enabled         = var.bucket_versioning_enabled
    public_access_prevention   = "enforced"
  }
}

output "function_security_config" {
  description = "Cloud Functions security configuration"
  value = {
    ingress_settings          = "ALLOW_ALL"
    service_accounts_created  = var.create_service_accounts
    invoker_permissions      = "allUsers (for demo - restrict in production)"
  }
}

# Data Organization Information
output "data_organization_guide" {
  description = "Guide to data organization in the bucket"
  value = {
    raw_conversations     = "gs://${google_storage_bucket.training_data.name}/raw-conversations/ - Generated conversations from Gemini"
    processed_conversations = "gs://${google_storage_bucket.training_data.name}/processed-conversations/ - Processed metadata and statistics"
    formatted_training    = "gs://${google_storage_bucket.training_data.name}/formatted-training/ - Training-ready data in multiple formats"
    templates            = "gs://${google_storage_bucket.training_data.name}/templates/ - Conversation generation templates"
    logs                 = var.enable_monitoring ? "gs://${google_storage_bucket.training_data.name}/logs/ - Function execution logs" : "Not configured"
  }
}

# Resource Identifiers for Cleanup
output "resource_identifiers" {
  description = "Resource identifiers for easy cleanup and management"
  value = {
    bucket_name             = google_storage_bucket.training_data.name
    generator_function_name = google_cloudfunctions2_function.conversation_generator.name
    processor_function_name = google_cloudfunctions2_function.data_processor.name
    generator_sa_email      = var.create_service_accounts ? google_service_account.generator_function_sa[0].email : null
    processor_sa_email      = var.create_service_accounts ? google_service_account.processor_function_sa[0].email : null
    resource_suffix         = random_id.suffix.hex
  }
}