# ============================================================================
# Smart Email Template Generation with Gemini and Firestore - Outputs
# ============================================================================
# This file defines the output values that will be displayed after successful
# deployment of the AI-powered email template generator infrastructure.
# These outputs provide essential information for testing and integration.
# ============================================================================

# ============================================================================
# CLOUD FUNCTION OUTPUTS
# ============================================================================

output "function_name" {
  description = "The name of the deployed Cloud Function for email template generation"
  value       = google_cloudfunctions2_function.email_template_generator.name
}

output "function_url" {
  description = "The HTTPS URL endpoint for the email template generation Cloud Function"
  value       = google_cloudfunctions2_function.email_template_generator.service_config[0].uri
  sensitive   = false
}

output "function_region" {
  description = "The region where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.email_template_generator.location
}

output "function_service_account" {
  description = "The service account email used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_status" {
  description = "The current state of the Cloud Function"
  value       = google_cloudfunctions2_function.email_template_generator.state
}

# ============================================================================
# FIRESTORE DATABASE OUTPUTS
# ============================================================================

output "firestore_database_name" {
  description = "The name of the created Firestore database for storing email templates and preferences"
  value       = google_firestore_database.email_templates.name
}

output "firestore_database_id" {
  description = "The full database ID including project and location information"
  value       = google_firestore_database.email_templates.id
}

output "firestore_location" {
  description = "The location where the Firestore database is hosted"
  value       = google_firestore_database.email_templates.location_id
}

output "firestore_type" {
  description = "The type of Firestore database (FIRESTORE_NATIVE)"
  value       = google_firestore_database.email_templates.type
}

# ============================================================================
# STORAGE OUTPUTS
# ============================================================================

output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "storage_bucket_url" {
  description = "The URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

# ============================================================================
# PROJECT AND ENVIRONMENT OUTPUTS
# ============================================================================

output "project_id" {
  description = "The Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "project_number" {
  description = "The Google Cloud Project number"
  value       = data.google_project.project.number
}

output "deployment_region" {
  description = "The primary region for resource deployment"
  value       = var.region
}

output "environment" {
  description = "The deployment environment (development, staging, production, etc.)"
  value       = var.environment
}

# ============================================================================
# VERTEX AI CONFIGURATION OUTPUTS
# ============================================================================

output "vertex_ai_location" {
  description = "The location configured for Vertex AI services"
  value       = var.vertex_ai_location
}

output "gemini_model" {
  description = "The Gemini model configured for email template generation"
  value       = var.gemini_model
}

# ============================================================================
# SECURITY AND IAM OUTPUTS
# ============================================================================

output "service_account_id" {
  description = "The unique ID of the service account created for the Cloud Function"
  value       = google_service_account.function_sa.unique_id
}

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "monitoring_enabled" {
  description = "Whether Cloud Monitoring alerts are enabled"
  value       = var.enable_monitoring
}

output "notification_channels" {
  description = "Monitoring notification channels configured for alerts"
  value = var.enable_monitoring && var.notification_email != "" ? [
    google_monitoring_notification_channel.email[0].name
  ] : []
}

output "alert_policies" {
  description = "Alert policies configured for the email template generator"
  value = var.enable_monitoring ? [
    google_monitoring_alert_policy.function_errors[0].name
  ] : []
}

# ============================================================================
# DATA INITIALIZATION OUTPUTS
# ============================================================================

output "sample_data_initialized" {
  description = "Whether sample data initialization was configured"
  value       = var.initialize_sample_data
}

output "data_initializer_function" {
  description = "The name of the data initialization function (if created)"
  value       = var.initialize_sample_data ? google_cloudfunctions2_function.data_initializer[0].name : null
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "test_curl_command" {
  description = "Sample curl command to test the email template generation function"
  value = templatefile("${path.module}/test_commands.tpl", {
    function_url = google_cloudfunctions2_function.email_template_generator.service_config[0].uri
  })
}

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_function_status = "gcloud functions describe ${google_cloudfunctions2_function.email_template_generator.name} --gen2 --region=${var.region}"
    check_firestore       = "gcloud firestore databases describe ${google_firestore_database.email_templates.name}"
    test_function_basic   = "curl -X GET '${google_cloudfunctions2_function.email_template_generator.service_config[0].uri}' -H 'Content-Type: application/json'"
  }
}

# ============================================================================
# RESOURCE IDENTIFIERS
# ============================================================================

output "random_suffix" {
  description = "The random suffix used for resource naming to ensure uniqueness"
  value       = random_id.suffix.hex
}

output "resource_labels" {
  description = "Common labels applied to all resources for organization"
  value = {
    environment = var.environment
    application = "email-template-generator"
    managed-by  = "terraform"
    recipe-id   = "f4a7b2c9"
  }
}

# ============================================================================
# COST AND CONFIGURATION OUTPUTS
# ============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD) for the deployed resources"
  value = {
    cloud_function_invocations = "Free tier: 2M invocations/month, then $0.40/1M invocations"
    cloud_function_compute     = "Free tier: 400K GB-seconds/month, then $0.0000025/GB-second"
    firestore_operations       = "Free tier: 50K reads, 20K writes/day, then $0.06/100K operations"
    vertex_ai_gemini          = "Varies by model: Flash ~$0.075/1K input tokens, ~$0.30/1K output tokens"
    cloud_storage             = "~$0.02/GB/month for Standard storage"
    note                      = "Actual costs depend on usage patterns and may qualify for free tier"
  }
}

output "configuration_summary" {
  description = "Summary of key configuration settings for the deployment"
  value = {
    function_memory               = var.function_memory
    function_timeout              = "${var.function_timeout}s"
    function_max_instances        = var.function_max_instances
    firestore_location           = var.firestore_location
    deletion_protection_enabled  = var.enable_deletion_protection
    monitoring_enabled           = var.enable_monitoring
    unauthenticated_access       = var.allow_unauthenticated_invocations
  }
}

# ============================================================================
# INTEGRATION OUTPUTS
# ============================================================================

output "api_endpoints" {
  description = "API endpoints for integration with external systems"
  value = {
    generate_template = "${google_cloudfunctions2_function.email_template_generator.service_config[0].uri}"
    health_check     = "${google_cloudfunctions2_function.email_template_generator.service_config[0].uri}/health"
  }
}

output "firestore_collections" {
  description = "Firestore collections used by the email template generator"
  value = {
    user_preferences    = "userPreferences"
    campaign_types      = "campaignTypes"
    generated_templates = "generatedTemplates"
  }
}

# ============================================================================
# TROUBLESHOOTING OUTPUTS
# ============================================================================

output "troubleshooting_commands" {
  description = "Commands for troubleshooting common issues"
  value = {
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.email_template_generator.name} --gen2 --region=${var.region}"
    check_iam_policies = "gcloud projects get-iam-policy ${var.project_id}"
    test_firestore     = "gcloud firestore databases list --project=${var.project_id}"
    check_apis         = "gcloud services list --enabled --project=${var.project_id}"
  }
}

output "common_issues" {
  description = "Common issues and their solutions"
  value = {
    function_timeout = "If function times out, increase timeout value in variables.tf"
    quota_exceeded   = "Check Vertex AI quotas in Google Cloud Console if getting quota errors"
    permission_denied = "Verify service account has required IAM roles for Firestore and Vertex AI"
    cors_errors      = "Update cors_origins variable if experiencing CORS issues in web applications"
  }
}

# ============================================================================
# NEXT STEPS OUTPUTS
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the function using the provided curl command",
    "2. Initialize sample data if not already done",
    "3. Integrate the function URL with your application",
    "4. Configure monitoring alerts with your email address",
    "5. Review and adjust memory/timeout settings based on usage patterns",
    "6. Consider enabling authentication for production use",
    "7. Set up CI/CD pipeline for function updates"
  ]
}