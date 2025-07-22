# Outputs for GCP Intelligent Resource Allocation with Cloud Quotas API and Cloud Run GPU

# Resource identifiers
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP Region"
  value       = var.region
}

# Cloud Storage outputs
output "quota_policies_bucket_name" {
  description = "Name of the Cloud Storage bucket containing quota policies"
  value       = google_storage_bucket.quota_policies.name
}

output "quota_policies_bucket_url" {
  description = "URL of the Cloud Storage bucket containing quota policies"
  value       = google_storage_bucket.quota_policies.url
}

# Firestore outputs
output "firestore_database_name" {
  description = "Name of the Firestore database for usage history"
  value       = google_firestore_database.quota_history.name
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.quota_history.location_id
}

# Cloud Function outputs
output "quota_manager_function_name" {
  description = "Name of the quota manager Cloud Function"
  value       = google_cloudfunctions2_function.quota_manager.name
}

output "quota_manager_function_uri" {
  description = "URI of the quota manager Cloud Function"
  value       = google_cloudfunctions2_function.quota_manager.service_config[0].uri
}

output "quota_manager_function_url" {
  description = "HTTP trigger URL for the quota manager function"
  value       = google_cloudfunctions2_function.quota_manager.service_config[0].uri
}

# Cloud Run outputs
output "ai_inference_service_name" {
  description = "Name of the AI inference Cloud Run service"
  value       = google_cloud_run_v2_service.ai_inference.name
}

output "ai_inference_service_url" {
  description = "URL of the AI inference Cloud Run service"
  value       = google_cloud_run_v2_service.ai_inference.uri
}

output "ai_inference_service_location" {
  description = "Location of the AI inference Cloud Run service"
  value       = google_cloud_run_v2_service.ai_inference.location
}

# Artifact Registry outputs
output "artifact_registry_repository_id" {
  description = "ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.ai_inference.repository_id
}

output "container_image_uri" {
  description = "Full URI of the container image"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_inference.repository_id}/${local.service_name}:latest"
}

# Service Account outputs
output "quota_manager_service_account_email" {
  description = "Email of the quota manager service account"
  value       = google_service_account.quota_manager.email
}

output "ai_inference_service_account_email" {
  description = "Email of the AI inference service account"
  value       = google_service_account.ai_inference.email
}

# Cloud Scheduler outputs
output "quota_analysis_job_name" {
  description = "Name of the regular quota analysis scheduler job"
  value       = google_cloud_scheduler_job.quota_analysis.name
}

output "peak_analysis_job_name" {
  description = "Name of the peak hour analysis scheduler job"
  value       = google_cloud_scheduler_job.peak_analysis.name
}

output "quota_analysis_schedule" {
  description = "Schedule for regular quota analysis"
  value       = var.quota_analysis_schedule
}

output "peak_analysis_schedule" {
  description = "Schedule for peak hour analysis"
  value       = var.peak_analysis_schedule
}

# Monitoring outputs
output "monitoring_alert_policy_name" {
  description = "Name of the high GPU utilization alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.high_gpu_utilization[0].name : "disabled"
}

output "monitoring_dashboard_url" {
  description = "URL to access the monitoring dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${split("/", google_monitoring_dashboard.quota_dashboard[0].id)[3]}?project=${var.project_id}" : "disabled"
}

# Configuration outputs
output "gpu_configuration" {
  description = "GPU configuration for Cloud Run services"
  value = {
    gpu_type  = var.cloud_run_gpu_type
    gpu_count = var.cloud_run_gpu_count
    memory    = var.cloud_run_memory
    cpu       = var.cloud_run_cpu
  }
}

output "quota_thresholds" {
  description = "Quota management thresholds"
  value = {
    gpu_utilization_threshold = var.gpu_utilization_threshold
    max_gpu_quota            = var.max_gpu_quota
    min_gpu_quota            = var.min_gpu_quota
    max_cost_per_hour        = var.max_cost_per_hour
  }
}

# Testing endpoints
output "test_commands" {
  description = "Commands for testing the deployed infrastructure"
  value = {
    health_check = "curl ${google_cloud_run_v2_service.ai_inference.uri}/"
    inference_test = "curl -X POST ${google_cloud_run_v2_service.ai_inference.uri}/infer -H 'Content-Type: application/json' -d '{\"model\": \"test-model\", \"complexity\": \"medium\"}'"
    metrics_check = "curl ${google_cloud_run_v2_service.ai_inference.uri}/metrics"
    quota_analysis = "curl -X POST ${google_cloudfunctions2_function.quota_manager.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"project_id\": \"${var.project_id}\", \"region\": \"${var.region}\"}'"
  }
}

# Cost monitoring
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    note = "Costs depend on actual usage patterns and regional pricing"
    cloud_run_gpu = "~$50-200/month depending on GPU usage"
    cloud_function = "~$5-20/month for regular execution"
    storage = "~$1-5/month for policies and logs"
    monitoring = "~$5-15/month for custom metrics"
    firestore = "~$1-10/month for usage history"
    total_estimate = "~$62-250/month"
  }
}

# Cleanup commands
output "cleanup_commands" {
  description = "Commands to clean up the deployed resources"
  value = {
    terraform_destroy = "terraform destroy"
    manual_firestore_cleanup = "gcloud firestore databases delete --database='(default)' --project=${var.project_id}"
    manual_storage_cleanup = "gsutil -m rm -r gs://${google_storage_bucket.quota_policies.name}"
  }
}