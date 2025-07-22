# Project Information
output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone"
  value       = var.zone
}

# API Services
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = [for api in google_project_service.batch_processing_apis : api.service]
}

# Random Suffix for Resource Names
output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = random_id.resource_suffix.hex
  sensitive   = false
}

# Service Account
output "service_account_email" {
  description = "Email address of the service account"
  value       = google_service_account.batch_processor.email
}

output "service_account_id" {
  description = "ID of the service account"
  value       = google_service_account.batch_processor.account_id
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.batch_processor.unique_id
}

# Artifact Registry
output "artifact_registry_repository_id" {
  description = "ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.batch_registry.repository_id
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.batch_registry.repository_id}"
}

output "artifact_registry_repository_location" {
  description = "Location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.batch_registry.location
}

# Cloud Storage
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket"
  value       = google_storage_bucket.batch_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.batch_data.url
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.batch_data.location
}

output "storage_bucket_storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.batch_data.storage_class
}

# Container Image
output "container_image_url" {
  description = "Full URL of the container image"
  value       = local.container_image_url
}

output "container_image_tag" {
  description = "Tag of the container image"
  value       = "latest"
}

# Cloud Run Job
output "cloud_run_job_name" {
  description = "Name of the Cloud Run job"
  value       = google_cloud_run_v2_job.batch_processor.name
}

output "cloud_run_job_id" {
  description = "ID of the Cloud Run job"
  value       = google_cloud_run_v2_job.batch_processor.id
}

output "cloud_run_job_location" {
  description = "Location of the Cloud Run job"
  value       = google_cloud_run_v2_job.batch_processor.location
}

output "cloud_run_job_uri" {
  description = "URI of the Cloud Run job"
  value       = google_cloud_run_v2_job.batch_processor.uri
}

output "cloud_run_job_generation" {
  description = "Generation of the Cloud Run job"
  value       = google_cloud_run_v2_job.batch_processor.generation
}

# Cloud Run Job Execution API Endpoint
output "cloud_run_job_execution_endpoint" {
  description = "API endpoint for executing the Cloud Run job"
  value       = "https://run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.batch_processor.name}:run"
}

# Cloud Scheduler
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.batch_schedule.name
}

output "scheduler_job_id" {
  description = "ID of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.batch_schedule.id
}

output "scheduler_job_schedule" {
  description = "Cron schedule of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.batch_schedule.schedule
}

output "scheduler_job_timezone" {
  description = "Timezone of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.batch_schedule.time_zone
}

output "scheduler_job_state" {
  description = "State of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.batch_schedule.state
}

# Monitoring
output "log_metric_name" {
  description = "Name of the log-based metric"
  value       = var.enable_monitoring ? google_logging_metric.batch_job_executions[0].name : null
}

output "alert_policy_name" {
  description = "Name of the alerting policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.batch_job_failures[0].display_name : null
}

# IAM Roles
output "service_account_roles" {
  description = "List of IAM roles assigned to the service account"
  value = [
    "roles/storage.objectAdmin",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/run.invoker"
  ]
}

# Resource Names with Suffix
output "resource_names" {
  description = "Map of resource names with their suffixes"
  value = {
    service_account      = google_service_account.batch_processor.account_id
    artifact_registry    = google_artifact_registry_repository.batch_registry.repository_id
    storage_bucket       = google_storage_bucket.batch_data.name
    cloud_run_job        = google_cloud_run_v2_job.batch_processor.name
    scheduler_job        = google_cloud_scheduler_job.batch_schedule.name
    log_metric          = var.enable_monitoring ? google_logging_metric.batch_job_executions[0].name : null
    alert_policy        = var.enable_monitoring ? google_monitoring_alert_policy.batch_job_failures[0].display_name : null
  }
}

# Environment Variables
output "batch_environment_variables" {
  description = "Environment variables configured for the batch processing job"
  value = merge(
    var.batch_environment_variables,
    {
      BUCKET_NAME = google_storage_bucket.batch_data.name
      PROJECT_ID  = var.project_id
      REGION      = var.region
    }
  )
}

# Network Configuration
output "network_configuration" {
  description = "Network configuration for the batch processing job"
  value = {
    network = var.network_name
    subnet  = var.subnet_name
  }
}

# Build Configuration
output "build_configuration" {
  description = "Build configuration for the container image"
  value = {
    timeout      = var.build_timeout
    machine_type = var.build_machine_type
  }
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for cost estimation"
  value = {
    cloud_run_job_config = {
      cpu            = var.job_cpu
      memory         = var.job_memory
      task_timeout   = var.job_task_timeout
      max_retries    = var.job_max_retries
      parallelism    = var.job_parallelism
      task_count     = var.job_task_count
    }
    storage_bucket_config = {
      location      = google_storage_bucket.batch_data.location
      storage_class = var.bucket_storage_class
    }
    scheduler_config = {
      schedule = var.scheduler_cron_schedule
      timezone = var.scheduler_timezone
    }
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployed resources"
  value = {
    deployment_time = timestamp()
    terraform_version = ">=1.0"
    provider_versions = {
      google      = "~>5.0"
      google-beta = "~>5.0"
      random      = "~>3.4"
      time        = "~>0.9"
    }
    resource_count = {
      api_services        = length(var.enable_apis)
      iam_roles          = 4
      storage_buckets    = 1
      cloud_run_jobs     = 1
      scheduler_jobs     = 1
      monitoring_resources = var.enable_monitoring ? 2 : 0
    }
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for testing and validation"
  value = {
    test_job_execution = "gcloud run jobs execute ${google_cloud_run_v2_job.batch_processor.name} --region=${var.region} --wait"
    trigger_scheduler = "gcloud scheduler jobs run ${google_cloud_scheduler_job.batch_schedule.name} --location=${var.region}"
    view_logs = "gcloud logging read \"resource.type=\\\"cloud_run_job\\\" AND resource.labels.job_name=\\\"${google_cloud_run_v2_job.batch_processor.name}\\\"\" --limit=20"
    upload_sample_data = "echo 'sample data' | gsutil cp - gs://${google_storage_bucket.batch_data.name}/input/sample.txt"
    check_processed_data = "gsutil ls gs://${google_storage_bucket.batch_data.name}/output/"
  }
}

# Documentation Links
output "documentation_links" {
  description = "Links to relevant Google Cloud documentation"
  value = {
    cloud_run_jobs    = "https://cloud.google.com/run/docs/create-jobs"
    cloud_scheduler   = "https://cloud.google.com/scheduler/docs"
    artifact_registry = "https://cloud.google.com/artifact-registry/docs"
    cloud_storage     = "https://cloud.google.com/storage/docs"
    cloud_build       = "https://cloud.google.com/build/docs"
    monitoring        = "https://cloud.google.com/monitoring/docs"
  }
}