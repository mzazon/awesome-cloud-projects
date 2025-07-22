# Outputs for Multi-Language Customer Support Automation Infrastructure
# These outputs provide essential information for accessing and managing the deployed resources

# Project and Location Information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where resources are deployed"
  value       = var.zone
}

# Service Account Information
output "ai_services_service_account_email" {
  description = "Email address of the AI services service account"
  value       = google_service_account.ai_services.email
}

output "ai_services_service_account_id" {
  description = "Unique ID of the AI services service account"
  value       = google_service_account.ai_services.unique_id
}

output "ai_services_service_account_name" {
  description = "Full resource name of the AI services service account"
  value       = google_service_account.ai_services.name
}

# Storage Resources
output "customer_support_bucket_name" {
  description = "Name of the Cloud Storage bucket for customer support data"
  value       = google_storage_bucket.customer_support_storage.name
}

output "customer_support_bucket_url" {
  description = "Full URL of the Cloud Storage bucket for customer support data"
  value       = google_storage_bucket.customer_support_storage.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "Full URL of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.url
}

# Firestore Database
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.support_database.name
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.support_database.location_id
}

output "firestore_database_id" {
  description = "The database ID (always '(default)' for the default database)"
  value       = google_firestore_database.support_database.name
}

# Cloud Function Information
output "multilang_processor_function_name" {
  description = "Name of the multilingual processor Cloud Function"
  value       = google_cloudfunctions2_function.multilang_processor.name
}

output "multilang_processor_function_url" {
  description = "HTTPS trigger URL for the multilingual processor Cloud Function"
  value       = google_cloudfunctions2_function.multilang_processor.service_config[0].uri
}

output "multilang_processor_function_location" {
  description = "Location of the multilingual processor Cloud Function"
  value       = google_cloudfunctions2_function.multilang_processor.location
}

output "multilang_processor_function_id" {
  description = "Unique ID of the multilingual processor Cloud Function"
  value       = google_cloudfunctions2_function.multilang_processor.id
}

# Cloud Workflows Information
output "support_workflow_name" {
  description = "Name of the support orchestration workflow"
  value       = google_workflows_workflow.support_orchestrator.name
}

output "support_workflow_id" {
  description = "Unique ID of the support orchestration workflow"
  value       = google_workflows_workflow.support_orchestrator.id
}

output "support_workflow_region" {
  description = "Region of the support orchestration workflow"
  value       = google_workflows_workflow.support_orchestrator.region
}

# API Service Status
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
}

# Configuration File Locations
output "speech_config_location" {
  description = "Cloud Storage location of the speech configuration file"
  value       = "gs://${google_storage_bucket.customer_support_storage.name}/${google_storage_bucket_object.speech_config.name}"
}

output "translation_config_location" {
  description = "Cloud Storage location of the translation configuration file"
  value       = "gs://${google_storage_bucket.customer_support_storage.name}/${google_storage_bucket_object.translation_config.name}"
}

output "sentiment_config_location" {
  description = "Cloud Storage location of the sentiment analysis configuration file"
  value       = "gs://${google_storage_bucket.customer_support_storage.name}/${google_storage_bucket_object.sentiment_config.name}"
}

output "tts_config_location" {
  description = "Cloud Storage location of the text-to-speech configuration file"
  value       = "gs://${google_storage_bucket.customer_support_storage.name}/${google_storage_bucket_object.tts_config.name}"
}

# Monitoring Resources
output "function_error_rate_alert_policy_name" {
  description = "Name of the function error rate alert policy"
  value       = google_monitoring_alert_policy.function_error_rate.display_name
}

output "negative_sentiment_alert_policy_name" {
  description = "Name of the negative sentiment alert policy"
  value       = google_monitoring_alert_policy.negative_sentiment.display_name
}

output "monitoring_dashboard_url" {
  description = "URL to access the monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${basename(google_monitoring_dashboard.multilingual_support.id)}?project=${var.project_id}"
}

# Log-based Metrics
output "sentiment_score_metric_name" {
  description = "Name of the sentiment score log-based metric"
  value       = google_logging_metric.sentiment_score.name
}

output "language_detection_metric_name" {
  description = "Name of the language detection log-based metric"
  value       = google_logging_metric.language_detection.name
}

# Configuration Values
output "supported_languages" {
  description = "List of supported languages for the system"
  value       = var.supported_languages
}

output "language_names" {
  description = "Mapping of language codes to human-readable names"
  value       = var.language_names
}

output "tts_voice_configuration" {
  description = "Text-to-Speech voice configuration by language"
  value       = var.tts_voice_config
  sensitive   = false
}

# Resource Labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Deployment Information
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

output "deployment_timestamp" {
  description = "Timestamp of when the resources were deployed"
  value       = timestamp()
}

# Environment Configuration
output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

output "cost_center" {
  description = "Cost center for billing and resource tracking"
  value       = var.cost_center
}

# Endpoint URLs for Integration
output "speech_to_text_api_endpoint" {
  description = "Endpoint for the Cloud Speech-to-Text API"
  value       = "https://speech.googleapis.com"
}

output "translation_api_endpoint" {
  description = "Endpoint for the Cloud Translation API"
  value       = "https://translate.googleapis.com"
}

output "natural_language_api_endpoint" {
  description = "Endpoint for the Cloud Natural Language API"
  value       = "https://language.googleapis.com"
}

output "text_to_speech_api_endpoint" {
  description = "Endpoint for the Cloud Text-to-Speech API"
  value       = "https://texttospeech.googleapis.com"
}

# Sample curl command for testing
output "function_test_command" {
  description = "Sample curl command to test the multilingual processor function"
  value = <<-EOT
    curl -X POST \
      -H "Content-Type: application/json" \
      -d '{
        "audio_data": "$(base64 -w 0 your-audio-file.wav)",
        "customer_id": "test-customer-123",
        "session_id": "test-session-$(date +%s)"
      }' \
      "${google_cloudfunctions2_function.multilang_processor.service_config[0].uri}"
  EOT
}

# gcloud commands for managing the deployment
output "useful_gcloud_commands" {
  description = "Useful gcloud commands for managing the deployment"
  value = {
    view_function_logs = "gcloud functions logs read ${local.function_name} --region=${var.region} --limit=50"
    view_workflow_executions = "gcloud workflows executions list --workflow=${local.workflow_name} --location=${var.region}"
    list_firestore_collections = "gcloud firestore collections list --database=${google_firestore_database.support_database.name}"
    check_storage_usage = "gsutil du -sh gs://${google_storage_bucket.customer_support_storage.name}"
    view_monitoring_dashboard = "gcloud monitoring dashboards list --filter='displayName:Multilingual Customer Support Dashboard'"
  }
}

# Security and Access Information
output "iam_roles_assigned" {
  description = "IAM roles assigned to the AI services service account"
  value = [
    for role in google_project_iam_member.ai_services_permissions : role.role
  ]
}

# Cost Estimation Information
output "cost_estimation_note" {
  description = "Information about potential costs for this deployment"
  value = <<-EOT
    This deployment includes pay-per-use services. Estimated monthly costs:
    - Cloud Functions: $0.40 per million requests + $0.0025 per GB-second
    - AI APIs: Variable based on usage (Speech-to-Text ~$0.006/15 seconds, Translation ~$20/million characters)
    - Cloud Storage: $0.020 per GB/month for Standard class
    - Firestore: $0.18 per 100K reads, $0.18 per 100K writes
    - Monitoring: Included in Google Cloud free tier for basic usage
    
    For detailed pricing, visit: https://cloud.google.com/pricing
  EOT
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = <<-EOT
    1. Test the function endpoint: ${google_cloudfunctions2_function.multilang_processor.service_config[0].uri}
    2. Configure notification channels for alerts if needed
    3. Upload sample audio files to test the pipeline
    4. Monitor usage in the Cloud Console dashboard
    5. Review and adjust sentiment thresholds based on your use case
    6. Consider setting up custom domains for production use
    7. Implement additional security measures like API keys or OAuth
  EOT
}

# Documentation Links
output "documentation_links" {
  description = "Useful documentation links for the deployed services"
  value = {
    speech_to_text = "https://cloud.google.com/speech-to-text/docs"
    translation = "https://cloud.google.com/translate/docs"
    natural_language = "https://cloud.google.com/natural-language/docs"
    text_to_speech = "https://cloud.google.com/text-to-speech/docs"
    cloud_functions = "https://cloud.google.com/functions/docs"
    workflows = "https://cloud.google.com/workflows/docs"
    firestore = "https://cloud.google.com/firestore/docs"
    monitoring = "https://cloud.google.com/monitoring/docs"
  }
}