# Project Information
output "project_id" {
  description = "The Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region used for deployment"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone used for zonal resources"
  value       = var.zone
}

# Storage Resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for ML training data"
  value       = google_storage_bucket.ml_training_bucket.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_training_bucket.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_training_bucket.self_link
}

# TPU Resources
output "tpu_name" {
  description = "Name of the Cloud TPU v6e instance"
  value       = google_tpu_node.training_tpu.name
}

output "tpu_accelerator_type" {
  description = "Accelerator type of the TPU instance"
  value       = google_tpu_node.training_tpu.accelerator_type
}

output "tpu_tensorflow_version" {
  description = "TensorFlow version running on the TPU"
  value       = google_tpu_node.training_tpu.tensorflow_version
}

output "tpu_network_endpoints" {
  description = "Network endpoints for the TPU instance"
  value       = google_tpu_node.training_tpu.network_endpoints
  sensitive   = false
}

output "tpu_service_account" {
  description = "Service account email used by the TPU"
  value       = google_tpu_node.training_tpu.service_account
}

# Dataproc Resources
output "dataproc_batch_id" {
  description = "ID of the Dataproc Serverless batch job"
  value       = google_dataproc_batch.preprocessing_batch.batch_id
}

output "dataproc_batch_state" {
  description = "Current state of the Dataproc batch job"
  value       = google_dataproc_batch.preprocessing_batch.state
}

output "dataproc_batch_create_time" {
  description = "Creation time of the Dataproc batch job"
  value       = google_dataproc_batch.preprocessing_batch.create_time
}

# Vertex AI Resources
output "vertex_ai_job_name" {
  description = "Name of the Vertex AI custom training job"
  value       = google_vertex_ai_custom_job.tpu_training_job.name
}

output "vertex_ai_job_display_name" {
  description = "Display name of the Vertex AI training job"
  value       = google_vertex_ai_custom_job.tpu_training_job.display_name
}

output "vertex_ai_job_state" {
  description = "Current state of the Vertex AI training job"
  value       = google_vertex_ai_custom_job.tpu_training_job.state
}

# Service Account
output "service_account_email" {
  description = "Email address of the ML pipeline service account"
  value       = google_service_account.ml_pipeline_sa.email
}

output "service_account_unique_id" {
  description = "Unique ID of the ML pipeline service account"
  value       = google_service_account.ml_pipeline_sa.unique_id
}

# Monitoring Resources
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard"
  value       = var.enable_monitoring ? google_monitoring_dashboard.tpu_training_dashboard[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL to access the Cloud Monitoring dashboard"
  value = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${split("/", google_monitoring_dashboard.tpu_training_dashboard[0].id)[3]}?project=${var.project_id}" : null
}

output "alert_policy_name" {
  description = "Name of the alerting policy for TPU training"
  value       = var.enable_monitoring && length(var.alert_notification_channels) > 0 ? google_monitoring_alert_policy.tpu_training_alerts[0].name : null
}

# Cloud Function
output "pipeline_orchestrator_function_name" {
  description = "Name of the pipeline orchestrator Cloud Function"
  value       = google_cloudfunctions2_function.pipeline_orchestrator.name
}

output "pipeline_orchestrator_function_uri" {
  description = "URI of the pipeline orchestrator Cloud Function"
  value       = google_cloudfunctions2_function.pipeline_orchestrator.service_config[0].uri
}

# Network Resources
output "firewall_rule_name" {
  description = "Name of the firewall rule for TPU communication"
  value       = google_compute_firewall.tpu_firewall.name
}

output "firewall_rule_self_link" {
  description = "Self-link of the firewall rule"
  value       = google_compute_firewall.tpu_firewall.self_link
}

# Training Data Paths
output "raw_data_path" {
  description = "Cloud Storage path for raw training data"
  value       = "gs://${google_storage_bucket.ml_training_bucket.name}/raw-data/"
}

output "processed_data_path" {
  description = "Cloud Storage path for processed training data"
  value       = "gs://${google_storage_bucket.ml_training_bucket.name}/processed-data/"
}

output "models_output_path" {
  description = "Cloud Storage path for trained models"
  value       = "gs://${google_storage_bucket.ml_training_bucket.name}/models/"
}

output "checkpoints_path" {
  description = "Cloud Storage path for training checkpoints"
  value       = "gs://${google_storage_bucket.ml_training_bucket.name}/checkpoints/"
}

output "logs_path" {
  description = "Cloud Storage path for training logs"
  value       = "gs://${google_storage_bucket.ml_training_bucket.name}/logs/"
}

# Resource Labels
output "applied_labels" {
  description = "Labels applied to all resources"
  value       = var.resource_labels
}

# Useful Commands
output "useful_commands" {
  description = "Useful commands for managing the ML training pipeline"
  value = {
    check_tpu_status = "gcloud compute tpus describe ${google_tpu_node.training_tpu.name} --zone=${var.zone}"
    check_dataproc_batch = "gcloud dataproc batches describe ${google_dataproc_batch.preprocessing_batch.batch_id} --region=${var.region}"
    check_vertex_ai_job = "gcloud ai custom-jobs describe ${google_vertex_ai_custom_job.tpu_training_job.name} --region=${var.region}"
    ssh_to_tpu = "gcloud compute tpus tpu-vm ssh ${google_tpu_node.training_tpu.name} --zone=${var.zone}"
    list_bucket_contents = "gsutil ls -la gs://${google_storage_bucket.ml_training_bucket.name}/"
    view_logs = "gcloud logging read 'resource.type=\"tpu_worker\"' --limit=50"
    monitoring_dashboard = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${split("/", google_monitoring_dashboard.tpu_training_dashboard[0].id)[3]}?project=${var.project_id}" : "Monitoring disabled"
  }
}

# Cost Estimation Information
output "estimated_hourly_costs" {
  description = "Estimated hourly costs for running resources (in USD, approximate)"
  value = {
    tpu_v6e_8_cores = "Approximately $2.40-$3.20 per hour (varies by region and preemptible status)"
    dataproc_serverless = "Pay-per-use based on vCPU-hours and memory-hours consumed"
    cloud_storage = "Minimal cost for storage, with additional charges for operations"
    vertex_ai_training = "Included in TPU costs when using TPU resources"
    monitoring_logging = "First 50GB of logs per month are free"
    total_estimated = "Approximately $2.50-$3.50 per hour when TPU is running"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    service_account = "Dedicated service account with minimal required permissions"
    uniform_bucket_access = var.bucket_uniform_access ? "Enabled" : "Disabled"
    firewall_rules = "Restricted to specified source ranges: ${join(", ", var.firewall_source_ranges)}"
    preemptible_tpu = var.enable_preemptible_tpu ? "Enabled (cost-optimized but less reliable)" : "Disabled (production-ready)"
    bucket_versioning = var.bucket_versioning_enabled ? "Enabled" : "Disabled"
  }
}