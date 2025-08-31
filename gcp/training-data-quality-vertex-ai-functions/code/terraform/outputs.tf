# =============================================================================
# Outputs for Training Data Quality Assessment Infrastructure
# =============================================================================

# -----------------------------------------------------------------------------
# Project and Location Information
# -----------------------------------------------------------------------------

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = data.google_project.current.project_id
}

output "project_number" {
  description = "The GCP project number"
  value       = data.google_project.current.number
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

# -----------------------------------------------------------------------------
# Cloud Storage Outputs
# -----------------------------------------------------------------------------

output "bucket_name" {
  description = "Name of the Cloud Storage bucket for training data and reports"
  value       = google_storage_bucket.data_quality_bucket.name
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.data_quality_bucket.url
}

output "bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.data_quality_bucket.self_link
}

output "datasets_folder_url" {
  description = "URL for uploading training datasets"
  value       = "gs://${google_storage_bucket.data_quality_bucket.name}/datasets/"
}

output "reports_folder_url" {
  description = "URL where analysis reports are stored"
  value       = "gs://${google_storage_bucket.data_quality_bucket.name}/reports/"
}

output "sample_data_location" {
  description = "Location of the sample training data for testing"
  value       = "gs://${google_storage_bucket.data_quality_bucket.name}/${google_storage_bucket_object.sample_data.name}"
}

# -----------------------------------------------------------------------------
# Cloud Function Outputs
# -----------------------------------------------------------------------------

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions_function.data_quality_analyzer.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.data_quality_analyzer.https_trigger_url
}

output "function_source_location" {
  description = "Location of the function source code in Cloud Storage"
  value       = "gs://${google_storage_bucket.data_quality_bucket.name}/${google_storage_bucket_object.function_source.name}"
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions_function.data_quality_analyzer.region
}

output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = google_cloudfunctions_function.data_quality_analyzer.runtime
}

# -----------------------------------------------------------------------------
# Service Account Outputs
# -----------------------------------------------------------------------------

output "service_account_email" {
  description = "Email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "service_account_name" {
  description = "Name of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.name
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.function_sa.unique_id
}

# -----------------------------------------------------------------------------
# Pub/Sub Outputs (Conditional)
# -----------------------------------------------------------------------------

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for data upload notifications (if enabled)"
  value       = var.enable_automatic_analysis ? google_pubsub_topic.data_upload_notifications[0].name : null
}

output "pubsub_topic_id" {
  description = "ID of the Pub/Sub topic for data upload notifications (if enabled)"
  value       = var.enable_automatic_analysis ? google_pubsub_topic.data_upload_notifications[0].id : null
}

# -----------------------------------------------------------------------------
# Monitoring Outputs (Conditional)
# -----------------------------------------------------------------------------

output "monitoring_dashboard_url" {
  description = "URL of the Cloud Monitoring dashboard (if enabled)"
  value = var.create_monitoring_dashboard ? (
    "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.data_quality_dashboard[0].id}?project=${data.google_project.current.project_id}"
  ) : null
}

# -----------------------------------------------------------------------------
# Testing and Usage Information
# -----------------------------------------------------------------------------

output "curl_test_command" {
  description = "Example curl command to test the Cloud Function"
  value = <<-EOT
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "project_id": "${data.google_project.current.project_id}",
    "region": "${var.region}",
    "bucket_name": "${google_storage_bucket.data_quality_bucket.name}",
    "dataset_path": "datasets/sample_training_data.json"
  }' \
  "${google_cloudfunctions_function.data_quality_analyzer.https_trigger_url}"
EOT
}

output "gcloud_test_command" {
  description = "Example gcloud command to invoke the Cloud Function"
  value = <<-EOT
gcloud functions call ${google_cloudfunctions_function.data_quality_analyzer.name} \
  --region=${var.region} \
  --data='{
    "project_id": "${data.google_project.current.project_id}",
    "region": "${var.region}",
    "bucket_name": "${google_storage_bucket.data_quality_bucket.name}",
    "dataset_path": "datasets/sample_training_data.json"
  }'
EOT
}

output "gsutil_upload_command" {
  description = "Example command to upload training data to the bucket"
  value = "gsutil cp your_training_data.json gs://${google_storage_bucket.data_quality_bucket.name}/datasets/"
}

output "gsutil_download_reports_command" {
  description = "Command to download analysis reports from the bucket"
  value = "gsutil cp -r gs://${google_storage_bucket.data_quality_bucket.name}/reports/ ./"
}

# -----------------------------------------------------------------------------
# Configuration Values for Reference
# -----------------------------------------------------------------------------

output "configuration_summary" {
  description = "Summary of key configuration values"
  value = {
    environment                    = var.environment
    function_memory_mb            = var.function_memory_mb
    function_timeout_seconds      = var.function_timeout_seconds
    vertex_ai_model              = var.vertex_ai_model
    bias_detection_threshold     = var.bias_detection_threshold
    vocabulary_diversity_threshold = var.vocabulary_diversity_threshold
    sample_size_for_analysis     = var.sample_size_for_analysis
    daily_api_call_limit         = var.daily_api_call_limit
    bucket_lifecycle_days        = var.bucket_lifecycle_days
    allow_unauthenticated        = var.allow_unauthenticated
    enable_automatic_analysis    = var.enable_automatic_analysis
    create_monitoring_dashboard  = var.create_monitoring_dashboard
  }
}

# -----------------------------------------------------------------------------
# Quick Start Guide
# -----------------------------------------------------------------------------

output "quick_start_guide" {
  description = "Quick start guide for using the deployed infrastructure"
  value = <<-EOT

=== Training Data Quality Assessment - Quick Start Guide ===

1. Upload your training data:
   gsutil cp your_training_data.json gs://${google_storage_bucket.data_quality_bucket.name}/datasets/

2. Trigger analysis via HTTP:
   curl -X POST -H "Content-Type: application/json" -d '{
     "project_id": "${data.google_project.current.project_id}",
     "region": "${var.region}",
     "bucket_name": "${google_storage_bucket.data_quality_bucket.name}",
     "dataset_path": "datasets/your_training_data.json"
   }' "${google_cloudfunctions_function.data_quality_analyzer.https_trigger_url}"

3. Check analysis results:
   gsutil ls gs://${google_storage_bucket.data_quality_bucket.name}/reports/

4. Download the latest report:
   gsutil cp gs://${google_storage_bucket.data_quality_bucket.name}/reports/quality_report_*.json ./

5. Monitor function logs:
   gcloud functions logs read ${google_cloudfunctions_function.data_quality_analyzer.name} --region=${var.region}

${var.create_monitoring_dashboard ? "6. View monitoring dashboard:\n   https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.data_quality_dashboard[0].id}?project=${data.google_project.current.project_id}" : ""}

EOT
}

# -----------------------------------------------------------------------------
# Cost Estimation Information
# -----------------------------------------------------------------------------

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources (USD)"
  value = {
    cloud_storage_gb_month = "~$0.023 per GB/month (Standard storage)"
    cloud_function_invocations = "~$0.0000004 per invocation (first 2M free)"
    cloud_function_compute_time = "~$0.0000025 per 100ms of compute time"
    vertex_ai_gemini_calls = "~$0.0010 per 1K input tokens, ~$0.0020 per 1K output tokens"
    cloud_monitoring = "~$0.258 per million data points ingested"
    pubsub_messages = var.enable_automatic_analysis ? "~$0.06 per million messages" : "Not enabled"
    estimated_monthly_total = "$5-25 depending on usage patterns and data volume"
  }
}

# -----------------------------------------------------------------------------
# Security and Compliance Information
# -----------------------------------------------------------------------------

output "security_configuration" {
  description = "Security configuration details"
  value = {
    service_account_principle = "Dedicated service account with minimal required permissions"
    vertex_ai_access = "Limited to aiplatform.user role"
    storage_access = "Limited to designated bucket only"
    function_network_access = var.ingress_settings
    bucket_public_access = "Prevented via uniform bucket-level access"
    https_only = "All function triggers use HTTPS only"
    authentication_required = var.allow_unauthenticated ? "Disabled for testing" : "Required"
  }
}

# -----------------------------------------------------------------------------
# Vertex AI and ML Configuration
# -----------------------------------------------------------------------------

output "ml_configuration" {
  description = "Machine learning and AI configuration details"
  value = {
    vertex_ai_model_used = var.vertex_ai_model
    bias_detection_metrics = ["Difference in Population Size", "Difference in Positive Proportions in True Labels (DPPTL)"]
    content_analysis_features = ["Language consistency", "Bias in language use", "Data quality issues", "Sentiment consistency", "Vocabulary diversity"]
    sample_analysis_size = "${var.sample_size_for_analysis} samples per analysis"
    api_rate_limits = "${var.daily_api_call_limit} calls per day"
  }
}

# -----------------------------------------------------------------------------
# Resource Identifiers for External Integration
# -----------------------------------------------------------------------------

output "resource_ids" {
  description = "Resource identifiers for external integration"
  value = {
    bucket_id = google_storage_bucket.data_quality_bucket.id
    function_id = google_cloudfunctions_function.data_quality_analyzer.id
    service_account_id = google_service_account.function_sa.id
    pubsub_topic_id = var.enable_automatic_analysis ? google_pubsub_topic.data_upload_notifications[0].id : null
    dashboard_id = var.create_monitoring_dashboard ? google_monitoring_dashboard.data_quality_dashboard[0].id : null
  }
}