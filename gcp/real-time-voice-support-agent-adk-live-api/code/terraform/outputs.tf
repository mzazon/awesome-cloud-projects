# Voice Support Agent Function Information
output "voice_agent_function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.voice_support_agent.name
}

output "voice_agent_function_url" {
  description = "HTTP trigger URL for the voice support agent function"
  value       = google_cloudfunctions2_function.voice_support_agent.service_config[0].uri
  sensitive   = false
}

output "voice_agent_function_id" {
  description = "Fully qualified resource ID of the Cloud Function"
  value       = google_cloudfunctions2_function.voice_support_agent.id
}

# Service Account Information
output "voice_agent_service_account_email" {
  description = "Email address of the service account used by the voice agent"
  value       = google_service_account.voice_agent_sa.email
}

output "voice_agent_service_account_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.voice_agent_sa.unique_id
}

# Storage Information
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

# Configuration Information
output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "vertex_ai_location" {
  description = "Location for Vertex AI resources"
  value       = var.vertex_ai_location
}

# Voice Agent Configuration
output "gemini_model" {
  description = "Gemini model version configured for the voice agent"
  value       = var.gemini_model
}

output "voice_name" {
  description = "Voice name configured for text-to-speech synthesis"
  value       = var.voice_name
}

output "language_code" {
  description = "Language code for speech processing"
  value       = var.language_code
}

# Monitoring Information
output "monitoring_dashboard_url" {
  description = "URL to the Cloud Monitoring dashboard for the voice agent"
  value = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.voice_agent_dashboard[0].id}?project=${var.project_id}" : "Monitoring disabled"
}

output "log_explorer_url" {
  description = "URL to view Cloud Function logs in Log Explorer"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions2_function.voice_support_agent.name}%22?project=${var.project_id}"
}

# Test and Client Information
output "test_client_instructions" {
  description = "Instructions for testing the voice support agent"
  value = <<-EOT
    1. Open the generated voice_test.html file in a web browser
    2. Click "Health Check" to verify the agent is running
    3. Click "Test Text Message" to test basic functionality
    4. Click "Initialize Voice Session" to test voice capabilities
    
    Direct API endpoint: ${google_cloudfunctions2_function.voice_support_agent.service_config[0].uri}
  EOT
}

output "curl_test_commands" {
  description = "Example curl commands for testing the voice agent"
  value = {
    health_check = "curl -X GET '${google_cloudfunctions2_function.voice_support_agent.service_config[0].uri}'"
    text_test = "curl -X POST '${google_cloudfunctions2_function.voice_support_agent.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"type\":\"text\",\"message\":\"Hello, I need help with my account\"}'"
    voice_session = "curl -X POST '${google_cloudfunctions2_function.voice_support_agent.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"type\":\"voice_start\",\"session_id\":\"test-session\"}'"
  }
}

# API Configuration for Client Integration
output "api_configuration" {
  description = "Configuration information for integrating with the voice agent API"
  value = {
    endpoint_url           = google_cloudfunctions2_function.voice_support_agent.service_config[0].uri
    supported_methods      = ["GET", "POST", "OPTIONS"]
    cors_enabled          = true
    authentication_required = !var.allow_unauthenticated
    content_type          = "application/json"
    
    # API endpoints
    endpoints = {
      health_check    = "GET /"
      text_interaction = "POST / with {\"type\":\"text\",\"message\":\"...\",\"customer_context\":{}}"
      voice_session   = "POST / with {\"type\":\"voice_start\",\"session_id\":\"...\"}"
    }
    
    # Response formats
    response_format = {
      success = "200 OK with JSON response"
      error   = "4xx/5xx with {\"error\":\"message\",\"details\":\"...\"}"
    }
  }
  sensitive = false
}

# Resource Labels and Metadata
output "resource_labels" {
  description = "Labels applied to all resources for organization and billing"
  value       = local.common_labels
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Feature Capabilities
output "agent_capabilities" {
  description = "List of capabilities enabled in the voice support agent"
  value = {
    customer_lookup      = var.customer_database_enabled
    ticket_creation     = var.ticket_system_enabled
    knowledge_search    = var.knowledge_base_enabled
    voice_streaming     = true
    real_time_response  = true
    function_calling    = true
    adk_integration     = true
    gemini_live_api     = true
  }
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources (USD)"
  value = {
    cloud_function_baseline = "~$0.40 (2M invocations)"
    vertex_ai_api_calls    = "~$3-8 per hour of active use"
    cloud_storage          = "~$0.02 for source code storage"
    cloud_logging          = "~$0.50 per GB of logs"
    cloud_monitoring       = "~$0.15 per metric stream"
    total_estimate         = "Varies based on usage: $5-20/month for development, $50-200/month for production"
    
    notes = [
      "Costs scale with API usage and conversation volume",
      "Gemini Live API charges per audio minute processed", 
      "Function compute time billed per 100ms increment",
      "Free tier quotas may apply for development usage"
    ]
  }
}

# Security Information
output "security_configuration" {
  description = "Security settings and recommendations for the voice agent"
  value = {
    service_account_principle = "Dedicated service account with minimal required permissions"
    api_access_control       = var.allow_unauthenticated ? "Public access enabled" : "Authenticated access required"
    encryption_at_rest       = "Enabled by default for all GCP services"
    encryption_in_transit    = "HTTPS/TLS for all API communications"
    
    iam_roles_granted = [
      "roles/aiplatform.user",
      "roles/cloudfunctions.invoker", 
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/cloudtrace.agent"
    ]
    
    recommendations = [
      "Enable authentication for production deployments",
      "Configure VPC networking for enhanced security",
      "Implement rate limiting for public endpoints",
      "Monitor function logs for security events",
      "Rotate service account keys regularly"
    ]
  }
}

# Deployment Information
output "deployment_metadata" {
  description = "Information about the deployed infrastructure"
  value = {
    terraform_version    = "~> 1.5"
    google_provider_version = "~> 5.0"
    deployment_timestamp = timestamp()
    
    deployed_resources = [
      "Cloud Function (Gen 2)",
      "Service Account", 
      "Cloud Storage Bucket",
      "IAM Policy Bindings",
      "Monitoring Dashboard",
      "Log-based Metrics",
      "Alert Policies"
    ]
    
    enabled_apis = [
      "aiplatform.googleapis.com",
      "cloudfunctions.googleapis.com", 
      "cloudbuild.googleapis.com",
      "logging.googleapis.com",
      "monitoring.googleapis.com",
      "speech.googleapis.com",
      "texttospeech.googleapis.com"
    ]
  }
}