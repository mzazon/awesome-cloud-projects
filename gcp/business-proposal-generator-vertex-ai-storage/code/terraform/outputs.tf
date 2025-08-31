# Project and deployment information
output "project_id" {
  description = "The Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

output "deployment_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Cloud Storage bucket information
output "templates_bucket_name" {
  description = "Name of the Cloud Storage bucket containing proposal templates"
  value       = google_storage_bucket.templates_bucket.name
}

output "templates_bucket_url" {
  description = "Self-link URL of the templates bucket"
  value       = google_storage_bucket.templates_bucket.self_link
}

output "client_data_bucket_name" {
  description = "Name of the Cloud Storage bucket for client data uploads (function trigger)"
  value       = google_storage_bucket.client_data_bucket.name
}

output "client_data_bucket_url" {
  description = "Self-link URL of the client data bucket"
  value       = google_storage_bucket.client_data_bucket.self_link
}

output "output_bucket_name" {
  description = "Name of the Cloud Storage bucket where generated proposals are stored"
  value       = google_storage_bucket.output_bucket.name
}

output "output_bucket_url" {
  description = "Self-link URL of the output bucket"
  value       = google_storage_bucket.output_bucket.self_link
}

# Cloud Function information
output "function_name" {
  description = "Name of the Cloud Function that generates proposals"
  value       = google_cloudfunctions2_function.proposal_generator.name
}

output "function_url" {
  description = "URL of the Cloud Function"
  value       = google_cloudfunctions2_function.proposal_generator.service_config[0].uri
}

output "function_trigger_region" {
  description = "Region where the function trigger is configured"
  value       = google_cloudfunctions2_function.proposal_generator.event_trigger[0].trigger_region
}

# Service account information
output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_service_account_id" {
  description = "Unique ID of the function service account"
  value       = google_service_account.function_sa.unique_id
}

# Configuration information
output "vertex_ai_model" {
  description = "Vertex AI model configured for proposal generation"
  value       = var.vertex_ai_model
}

output "vertex_ai_config" {
  description = "Vertex AI model configuration parameters"
  value = {
    model             = var.vertex_ai_model
    max_output_tokens = var.vertex_ai_max_tokens
    temperature       = var.vertex_ai_temperature
    top_p             = var.vertex_ai_top_p
    top_k             = var.vertex_ai_top_k
  }
}

# Monitoring information (conditional)
output "monitoring_topic_name" {
  description = "Name of the Pub/Sub topic for monitoring notifications (if enabled)"
  value       = var.enable_monitoring ? google_pubsub_topic.function_notifications[0].name : null
}

output "log_sink_name" {
  description = "Name of the log sink for function monitoring (if enabled)"
  value       = var.enable_monitoring ? google_logging_project_sink.function_logs[0].name : null
}

# Testing and usage information
output "testing_commands" {
  description = "Commands to test the proposal generation system"
  value = {
    upload_client_data = "gsutil cp client-data.json gs://${google_storage_bucket.client_data_bucket.name}/"
    list_generated_proposals = "gsutil ls gs://${google_storage_bucket.output_bucket.name}/"
    download_proposal = "gsutil cp gs://${google_storage_bucket.output_bucket.name}/proposal-*.txt ./"
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.proposal_generator.name} --region=${var.region} --limit=10"
  }
}

# Resource URLs for direct access
output "console_urls" {
  description = "Google Cloud Console URLs for accessing resources"
  value = {
    templates_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.templates_bucket.name}"
    client_data_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.client_data_bucket.name}"
    output_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.output_bucket.name}"
    cloud_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.proposal_generator.name}"
    vertex_ai = "https://console.cloud.google.com/vertex-ai"
  }
}

# Sample client data for testing
output "sample_client_data" {
  description = "Sample client data structure for testing the system"
  value = {
    filename = "client-data.json"
    content = jsonencode({
      client_name = "TechCorp Solutions"
      industry = "Financial Services"
      project_type = "Digital Transformation Initiative"
      requirements = [
        "Modernize legacy banking systems",
        "Implement cloud-native architecture",
        "Enhance mobile banking experience",
        "Ensure regulatory compliance"
      ]
      timeline = "6-month implementation"
      budget_range = "$500K - $1M"
      key_stakeholders = [
        "CTO - Technology Strategy",
        "Head of Digital - User Experience",
        "Compliance Officer - Regulatory Requirements"
      ]
      success_metrics = [
        "50% reduction in system response time",
        "90% customer satisfaction score",
        "100% regulatory compliance"
      ]
    })
  }
}

# Cost estimation information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources (in USD)"
  value = {
    note = "Costs are estimates and may vary based on actual usage"
    cloud_storage = "$1-5 per month (depending on data volume)"
    cloud_function = "$5-20 per month (depending on invocations)"
    vertex_ai = "$10-50 per month (depending on API calls)"
    total_estimated = "$16-75 per month"
    cost_factors = [
      "Vertex AI API calls are the primary cost driver",
      "Storage costs depend on data retention and volume",
      "Function costs scale with trigger frequency",
      "Network egress charges may apply for data transfer"
    ]
  }
}

# Security and compliance information
output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    uniform_bucket_access = var.bucket_uniform_access
    public_access_prevention = "enforced"
    service_account_permissions = [
      "roles/storage.admin",
      "roles/aiplatform.user",
      "roles/logging.logWriter"
    ]
    function_ingress = "ALLOW_INTERNAL_ONLY"
    api_security = "OAuth 2.0 and IAM-based authentication"
  }
}