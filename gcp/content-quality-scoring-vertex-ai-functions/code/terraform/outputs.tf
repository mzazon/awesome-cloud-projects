# ================================================================
# Outputs for Content Quality Scoring System
# ================================================================
# This file defines all output values that will be displayed
# after successful deployment and can be used by other Terraform
# configurations or external systems.
# ================================================================

# ================================================================
# PROJECT AND DEPLOYMENT INFORMATION
# ================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# ================================================================
# CLOUD STORAGE BUCKET INFORMATION
# ================================================================

output "content_bucket_name" {
  description = "Name of the Cloud Storage bucket for content uploads"
  value       = google_storage_bucket.content_bucket.name
}

output "content_bucket_url" {
  description = "URL of the content upload bucket"
  value       = google_storage_bucket.content_bucket.url
}

output "content_bucket_self_link" {
  description = "Self-link of the content upload bucket"
  value       = google_storage_bucket.content_bucket.self_link
}

output "results_bucket_name" {
  description = "Name of the Cloud Storage bucket for analysis results"
  value       = google_storage_bucket.results_bucket.name
}

output "results_bucket_url" {
  description = "URL of the results bucket"
  value       = google_storage_bucket.results_bucket.url
}

output "results_bucket_self_link" {
  description = "Self-link of the results bucket"
  value       = google_storage_bucket.results_bucket.self_link
}

# ================================================================
# CLOUD FUNCTION INFORMATION
# ================================================================

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.content_analyzer.name
}

output "function_id" {
  description = "Unique identifier of the Cloud Function"
  value       = google_cloudfunctions2_function.content_analyzer.id
}

output "function_uri" {
  description = "URI of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.content_analyzer.service_config[0].uri
}

output "function_url" {
  description = "Trigger URL of the Cloud Function"
  value       = google_cloudfunctions2_function.content_analyzer.url
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = google_cloudfunctions2_function.content_analyzer.build_config[0].runtime
}

output "function_memory" {
  description = "Memory allocation of the Cloud Function"
  value       = google_cloudfunctions2_function.content_analyzer.service_config[0].available_memory
}

output "function_timeout" {
  description = "Timeout configuration of the Cloud Function"
  value       = google_cloudfunctions2_function.content_analyzer.service_config[0].timeout_seconds
}

# ================================================================
# IAM AND SECURITY INFORMATION
# ================================================================

output "function_service_account_id" {
  description = "ID of the service account created for the Cloud Function"
  value       = google_service_account.function_sa.account_id
}

output "function_service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.function_sa.unique_id
}

# ================================================================
# MONITORING AND ALERTING INFORMATION
# ================================================================

output "monitoring_enabled" {
  description = "Whether monitoring and alerting are enabled"
  value       = var.enable_monitoring
}

output "notification_channel_id" {
  description = "ID of the monitoring notification channel (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.email[0].id : null
}

output "alert_policies" {
  description = "List of alert policy IDs (if monitoring is enabled)"
  value = var.enable_monitoring ? [
    google_monitoring_alert_policy.function_error_rate[0].id,
    google_monitoring_alert_policy.function_latency[0].id
  ] : []
}

# ================================================================
# USAGE INSTRUCTIONS
# ================================================================

output "usage_instructions" {
  description = "Instructions for using the deployed content quality scoring system"
  value = {
    upload_content = "Upload text files to: gs://${google_storage_bucket.content_bucket.name}/"
    view_results   = "View analysis results in: gs://${google_storage_bucket.results_bucket.name}/"
    upload_command = "gsutil cp your-content.txt gs://${google_storage_bucket.content_bucket.name}/"
    list_results   = "gsutil ls gs://${google_storage_bucket.results_bucket.name}/"
    download_result = "gsutil cp gs://${google_storage_bucket.results_bucket.name}/analysis_* ./results/"
  }
}

# ================================================================
# CONFIGURATION SUMMARY
# ================================================================

output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    environment                = var.environment
    function_runtime          = var.function_runtime
    function_memory           = var.function_memory
    function_timeout          = var.function_timeout
    function_max_instances    = var.function_max_instances
    storage_class             = var.storage_class
    content_retention_days    = var.content_retention_days
    results_retention_days    = var.results_retention_days
    vertex_ai_model          = var.vertex_ai_model
    monitoring_enabled       = var.enable_monitoring
  }
}

# ================================================================
# COST ESTIMATION INFORMATION
# ================================================================

output "cost_estimation" {
  description = "Estimated monthly costs and usage information"
  value = {
    message = "Cost depends on usage. Monitor Cloud Billing for actual costs."
    factors = [
      "Cloud Functions invocations and compute time",
      "Cloud Storage storage and operations",
      "Vertex AI API calls and token usage",
      "Cloud Build operations",
      "Network egress charges"
    ]
    cost_optimization_tips = [
      "Set appropriate function memory allocation",
      "Use lifecycle policies for storage cost optimization",
      "Monitor Vertex AI token usage",
      "Consider content length limits to control costs",
      "Use monitoring to identify optimization opportunities"
    ]
  }
}

# ================================================================
# TESTING AND VALIDATION
# ================================================================

output "testing_commands" {
  description = "Commands for testing the deployed system"
  value = {
    create_test_file = "echo 'This is test content for quality analysis.' > test-content.txt"
    upload_test_file = "gsutil cp test-content.txt gs://${google_storage_bucket.content_bucket.name}/"
    check_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.content_analyzer.name} --gen2 --region ${var.region} --limit 10"
    list_results = "gsutil ls gs://${google_storage_bucket.results_bucket.name}/"
    download_result = "gsutil cp gs://${google_storage_bucket.results_bucket.name}/analysis_test-content.txt_* ./test-result.json"
    view_result = "cat test-result.json | jq '.'"
  }
}

# ================================================================
# TROUBLESHOOTING INFORMATION
# ================================================================

output "troubleshooting" {
  description = "Troubleshooting commands and information"
  value = {
    check_function_status = "gcloud functions describe ${google_cloudfunctions2_function.content_analyzer.name} --gen2 --region ${var.region}"
    check_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.content_analyzer.name} --gen2 --region ${var.region} --filter='severity>=ERROR'"
    check_bucket_permissions = "gsutil iam get gs://${google_storage_bucket.content_bucket.name}"
    check_service_account = "gcloud iam service-accounts describe ${google_service_account.function_sa.email}"
    test_vertex_ai_access = "gcloud ai models list --region=${var.region}"
    common_issues = [
      "Ensure Vertex AI API is enabled in the project",
      "Verify service account has proper IAM permissions",
      "Check function logs for detailed error messages",
      "Confirm content files are in supported text formats",
      "Monitor quota limits for Vertex AI API usage"
    ]
  }
}

# ================================================================
# RESOURCE INFORMATION FOR EXTERNAL INTEGRATION
# ================================================================

output "resource_ids" {
  description = "Resource IDs for external integration or automation"
  value = {
    content_bucket_id = google_storage_bucket.content_bucket.id
    results_bucket_id = google_storage_bucket.results_bucket.id
    function_id = google_cloudfunctions2_function.content_analyzer.id
    service_account_id = google_service_account.function_sa.id
    project_number = data.google_project.current.number
  }
  sensitive = false
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# ================================================================
# SECURITY AND COMPLIANCE INFORMATION
# ================================================================

output "security_configuration" {
  description = "Security and compliance configuration details"
  value = {
    bucket_uniform_access = "Enabled on both buckets"
    bucket_versioning = "Enabled on both buckets"
    function_ingress = var.function_ingress_settings
    service_account_principle = "Dedicated service account with minimal permissions"
    encryption = "Google-managed encryption keys (default)"
    network_security = "Internal-only function access by default"
  }
}

# ================================================================
# API AND DEPENDENCY INFORMATION
# ================================================================

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com", 
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com"
  ]
}

output "python_dependencies" {
  description = "Python package versions used in the Cloud Function"
  value = {
    functions_framework = var.functions_framework_version
    google_cloud_storage = var.google_cloud_storage_version
    google_cloud_aiplatform = var.google_cloud_aiplatform_version
    google_cloud_logging = var.google_cloud_logging_version
  }
}