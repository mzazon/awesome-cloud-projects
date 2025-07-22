# Outputs for smart calendar intelligence infrastructure

# ============================================================================
# PROJECT AND ENVIRONMENT OUTPUTS
# ============================================================================

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

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# ============================================================================
# CLOUD RUN OUTPUTS
# ============================================================================

output "worker_pool_name" {
  description = "Name of the Cloud Run Worker Pool"
  value       = google_cloud_run_v2_worker_pool.calendar_intelligence.name
}

output "worker_pool_uri" {
  description = "URI of the Cloud Run Worker Pool"
  value       = google_cloud_run_v2_worker_pool.calendar_intelligence.uri
}

output "worker_pool_status" {
  description = "Current status of the Worker Pool"
  value = {
    ready      = length(google_cloud_run_v2_worker_pool.calendar_intelligence.conditions) > 0 ? google_cloud_run_v2_worker_pool.calendar_intelligence.conditions[0].state == "CONDITION_SUCCEEDED" : false
    generation = google_cloud_run_v2_worker_pool.calendar_intelligence.generation
    latest_ready_revision = google_cloud_run_v2_worker_pool.calendar_intelligence.latest_ready_revision
  }
}

output "api_service_name" {
  description = "Name of the Cloud Run API service"
  value       = google_cloud_run_v2_service.calendar_api.name
}

output "api_service_url" {
  description = "URL of the Cloud Run API service"
  value       = google_cloud_run_v2_service.calendar_api.uri
}

output "api_service_status" {
  description = "Current status of the API service"
  value = {
    ready      = length(google_cloud_run_v2_service.calendar_api.conditions) > 0 ? google_cloud_run_v2_service.calendar_api.conditions[0].state == "CONDITION_SUCCEEDED" : false
    generation = google_cloud_run_v2_service.calendar_api.generation
    latest_ready_revision = google_cloud_run_v2_service.calendar_api.latest_ready_revision
  }
}

# ============================================================================
# STORAGE AND DATA OUTPUTS
# ============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for artifacts"
  value       = google_storage_bucket.calendar_intelligence.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.calendar_intelligence.url
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for calendar analytics"
  value       = google_bigquery_dataset.calendar_analytics.dataset_id
}

output "bigquery_table_id" {
  description = "BigQuery table ID for calendar insights"
  value       = google_bigquery_table.calendar_insights.table_id
}

output "bigquery_table_reference" {
  description = "Full BigQuery table reference for SQL queries"
  value       = "${var.project_id}.${google_bigquery_dataset.calendar_analytics.dataset_id}.${google_bigquery_table.calendar_insights.table_id}"
}

# ============================================================================
# TASK QUEUE OUTPUTS
# ============================================================================

output "cloud_tasks_queue_name" {
  description = "Name of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.calendar_tasks.name
}

output "cloud_tasks_queue_id" {
  description = "Full resource ID of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.calendar_tasks.id
}

output "cloud_tasks_queue_stats" {
  description = "Cloud Tasks queue configuration"
  value = {
    max_concurrent_dispatches   = google_cloud_tasks_queue.calendar_tasks.rate_limits[0].max_concurrent_dispatches
    max_dispatches_per_second   = google_cloud_tasks_queue.calendar_tasks.rate_limits[0].max_dispatches_per_second
    max_retry_duration         = google_cloud_tasks_queue.calendar_tasks.retry_config[0].max_retry_duration
    max_attempts               = google_cloud_tasks_queue.calendar_tasks.retry_config[0].max_attempts
  }
}

# ============================================================================
# IAM OUTPUTS
# ============================================================================

output "worker_service_account_email" {
  description = "Email of the worker pool service account"
  value       = var.iam_config.create_service_accounts ? google_service_account.worker_service_account[0].email : null
}

output "api_service_account_email" {
  description = "Email of the API service account"
  value       = var.iam_config.create_service_accounts ? google_service_account.api_service_account[0].email : null
}

output "service_account_keys" {
  description = "Service account information for application configuration"
  value = var.iam_config.create_service_accounts ? {
    worker_account = {
      email        = google_service_account.worker_service_account[0].email
      unique_id    = google_service_account.worker_service_account[0].unique_id
      display_name = google_service_account.worker_service_account[0].display_name
    }
    api_account = {
      email        = google_service_account.api_service_account[0].email
      unique_id    = google_service_account.api_service_account[0].unique_id
      display_name = google_service_account.api_service_account[0].display_name
    }
  } : null
  sensitive = false
}

# ============================================================================
# ARTIFACT REGISTRY OUTPUTS
# ============================================================================

output "artifact_registry_repository" {
  description = "Artifact Registry repository information"
  value = {
    name         = google_artifact_registry_repository.calendar_intelligence.name
    location     = google_artifact_registry_repository.calendar_intelligence.location
    repository_id = google_artifact_registry_repository.calendar_intelligence.repository_id
    format       = google_artifact_registry_repository.calendar_intelligence.format
  }
}

output "container_registry_url" {
  description = "Full URL for pushing container images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.calendar_intelligence.repository_id}"
}

# ============================================================================
# SCHEDULER OUTPUTS
# ============================================================================

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for daily analysis"
  value       = var.scheduler_config.enable_scheduler ? google_cloud_scheduler_job.daily_analysis[0].name : null
}

output "scheduler_job_schedule" {
  description = "Schedule expression for the daily analysis job"
  value       = var.scheduler_config.enable_scheduler ? google_cloud_scheduler_job.daily_analysis[0].schedule : null
}

# ============================================================================
# SECRET MANAGER OUTPUTS
# ============================================================================

output "secret_manager_secret_name" {
  description = "Name of the Secret Manager secret for calendar credentials"
  value       = var.security_config.enable_secret_manager ? google_secret_manager_secret.calendar_credentials[0].secret_id : null
}

output "secret_manager_secret_id" {
  description = "Full resource ID of the Secret Manager secret"
  value       = var.security_config.enable_secret_manager ? google_secret_manager_secret.calendar_credentials[0].id : null
}

# ============================================================================
# MONITORING AND OBSERVABILITY OUTPUTS
# ============================================================================

output "monitoring_endpoints" {
  description = "Monitoring and observability endpoints"
  value = {
    cloud_logging_filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_worker_pool.calendar_intelligence.name}\""
    cloud_monitoring_dashboard = "https://console.cloud.google.com/monitoring/dashboards/resourceList/cloud_run_revision?project=${var.project_id}"
    cloud_trace_url = "https://console.cloud.google.com/traces/list?project=${var.project_id}"
  }
}

# ============================================================================
# DEPLOYMENT VERIFICATION OUTPUTS
# ============================================================================

output "deployment_verification" {
  description = "Commands and URLs for verifying the deployment"
  value = {
    api_health_check = "curl -X GET \"${google_cloud_run_v2_service.calendar_api.uri}/health\""
    trigger_analysis = "curl -X POST \"${google_cloud_run_v2_service.calendar_api.uri}/trigger-analysis\" -H \"Content-Type: application/json\" -d '{\"calendar_ids\": [\"primary\"]}'"
    
    bigquery_query = "bq query --use_legacy_sql=false \"SELECT calendar_id, analysis_timestamp, SUBSTR(insights, 1, 100) as insights_preview FROM \\`${var.project_id}.${google_bigquery_dataset.calendar_analytics.dataset_id}.${google_bigquery_table.calendar_insights.table_id}\\` ORDER BY analysis_timestamp DESC LIMIT 5\""
    
    task_queue_check = "gcloud tasks queues describe ${google_cloud_tasks_queue.calendar_tasks.name} --location=${var.region} --format=\"table(name,state,rateLimits.maxConcurrentDispatches)\""
    
    worker_pool_status = "gcloud beta run worker-pools describe ${google_cloud_run_v2_worker_pool.calendar_intelligence.name} --region=${var.region} --format=\"table(metadata.name,status.conditions[0].type,status.conditions[0].status)\""
  }
}

# ============================================================================
# COST OPTIMIZATION OUTPUTS
# ============================================================================

output "cost_optimization_info" {
  description = "Information for cost optimization and monitoring"
  value = {
    estimated_monthly_cost_usd = "15-25 (based on moderate usage)"
    
    cost_drivers = [
      "Vertex AI model inference calls",
      "BigQuery storage and analysis",
      "Cloud Run vCPU-seconds and memory allocation",
      "Cloud Tasks queue operations",
      "Cloud Storage API operations"
    ]
    
    cost_optimization_tips = [
      "Use Cloud Run min instances = 0 for cost-effective scaling",
      "Implement BigQuery table partitioning for large datasets",
      "Monitor Vertex AI model usage and consider batch processing",
      "Use Cloud Storage lifecycle policies for old data",
      "Review Cloud Tasks retry policies to avoid unnecessary executions"
    ]
  }
}

# ============================================================================
# TROUBLESHOOTING OUTPUTS
# ============================================================================

output "troubleshooting_info" {
  description = "Troubleshooting information and common issues"
  value = {
    common_issues = {
      "worker_pool_not_ready" = "Check service account permissions and API enablement status"
      "bigquery_permission_denied" = "Verify service account has bigquery.dataEditor role"
      "vertex_ai_quota_exceeded" = "Check Vertex AI quotas in Cloud Console"
      "cloud_tasks_queue_empty" = "Verify scheduler job is running and API service is accessible"
    }
    
    debug_commands = {
      check_apis = "gcloud services list --enabled --filter=\"name:(run.googleapis.com OR cloudtasks.googleapis.com OR aiplatform.googleapis.com)\""
      view_logs = "gcloud logs read \"resource.type=cloud_run_revision AND resource.labels.service_name=${google_cloud_run_v2_worker_pool.calendar_intelligence.name}\" --limit=50"
      test_permissions = "gcloud projects test-iam-permissions ${var.project_id} --permissions=aiplatform.models.predict,bigquery.tables.create,storage.objects.create"
    }
  }
}

# ============================================================================
# NEXT STEPS OUTPUTS
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    immediate_actions = [
      "Configure Google Calendar API credentials in Secret Manager",
      "Build and push container images to Artifact Registry",
      "Test the API endpoints using the provided curl commands",
      "Set up monitoring dashboards and alerts"
    ]
    
    configuration_steps = [
      "Update worker pool container image with your application code",
      "Configure domain-wide delegation for Google Workspace integration",
      "Set up custom Vertex AI model training if needed",
      "Configure additional calendar APIs and integrations"
    ]
    
    production_considerations = [
      "Enable Binary Authorization for container security",
      "Set up custom domain and SSL certificates", 
      "Implement comprehensive monitoring and alerting",
      "Configure backup and disaster recovery procedures",
      "Set up CI/CD pipelines for automated deployments"
    ]
  }
}