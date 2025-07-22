# Project and basic configuration outputs
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region used for resources"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Service account outputs
output "fleet_engine_service_account" {
  description = "Service account email for Fleet Engine operations"
  value       = google_service_account.fleet_engine_sa.email
}

output "fleet_engine_service_account_id" {
  description = "Service account ID for Fleet Engine operations"
  value       = google_service_account.fleet_engine_sa.account_id
}

output "fleet_engine_service_account_key" {
  description = "Service account key for Fleet Engine authentication (base64 encoded)"
  value       = google_service_account_key.fleet_engine_key.private_key
  sensitive   = true
}

# Storage outputs
output "fleet_data_bucket_name" {
  description = "Name of the Cloud Storage bucket for fleet data"
  value       = google_storage_bucket.fleet_data.name
}

output "fleet_data_bucket_url" {
  description = "URL of the Cloud Storage bucket for fleet data"
  value       = google_storage_bucket.fleet_data.url
}

output "fleet_data_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket for fleet data"
  value       = google_storage_bucket.fleet_data.self_link
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for fleet analytics"
  value       = google_bigquery_dataset.fleet_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.fleet_analytics.location
}

output "bigquery_dataset_self_link" {
  description = "Self-link of the BigQuery dataset"
  value       = google_bigquery_dataset.fleet_analytics.self_link
}

output "bigquery_tables" {
  description = "List of BigQuery tables created for fleet analytics"
  value = {
    vehicle_telemetry = {
      table_id   = google_bigquery_table.vehicle_telemetry.table_id
      self_link  = google_bigquery_table.vehicle_telemetry.self_link
    }
    route_performance = {
      table_id   = google_bigquery_table.route_performance.table_id
      self_link  = google_bigquery_table.route_performance.self_link
    }
    delivery_tasks = {
      table_id   = google_bigquery_table.delivery_tasks.table_id
      self_link  = google_bigquery_table.delivery_tasks.self_link
    }
  }
}

# Firestore outputs
output "firestore_database_name" {
  description = "Name of the Firestore database for real-time fleet state"
  value       = var.enable_firestore ? google_firestore_database.fleet_state[0].name : null
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = var.enable_firestore ? google_firestore_database.fleet_state[0].location_id : null
}

# Container registry outputs
output "container_registry_repository" {
  description = "Artifact Registry repository for fleet analytics containers"
  value       = google_artifact_registry_repository.fleet_containers.name
}

output "container_registry_url" {
  description = "URL of the container registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.fleet_containers.repository_id}"
}

output "analytics_container_image_url" {
  description = "Full URL of the analytics container image"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.fleet_containers.repository_id}/${var.container_image_name}:latest"
}

# Cloud Run Job outputs
output "analytics_job_name" {
  description = "Name of the Cloud Run job for fleet analytics"
  value       = google_cloud_run_v2_job.fleet_analytics.name
}

output "analytics_job_id" {
  description = "ID of the Cloud Run job for fleet analytics"
  value       = google_cloud_run_v2_job.fleet_analytics.id
}

output "analytics_job_location" {
  description = "Location of the Cloud Run job"
  value       = google_cloud_run_v2_job.fleet_analytics.location
}

output "analytics_job_uri" {
  description = "URI for triggering the analytics job"
  value       = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.fleet_analytics.name}:run"
}

# Cloud Scheduler outputs
output "scheduler_jobs" {
  description = "Details of the Cloud Scheduler jobs"
  value = var.enable_scheduler ? {
    daily_analytics = {
      name     = google_cloud_scheduler_job.daily_analytics[0].name
      schedule = google_cloud_scheduler_job.daily_analytics[0].schedule
    }
    hourly_insights = {
      name     = google_cloud_scheduler_job.hourly_insights[0].name
      schedule = google_cloud_scheduler_job.hourly_insights[0].schedule
    }
  } : {}
}

# Monitoring outputs
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard for fleet operations"
  value       = var.enable_monitoring ? google_monitoring_dashboard.fleet_operations[0].id : null
}

output "monitoring_notification_channel" {
  description = "Notification channel for monitoring alerts"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email_alerts[0].id : null
}

output "monitoring_alert_policy_id" {
  description = "ID of the alert policy for job failures"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.job_failure_alert[0].id : null
}

# Fleet Engine API endpoints
output "fleet_engine_api_endpoints" {
  description = "Fleet Engine API endpoints for integration"
  value = {
    delivery_api = "https://fleetengine.googleapis.com/v1/providers/${var.project_id}"
    vehicles     = "https://fleetengine.googleapis.com/v1/providers/${var.project_id}/vehicles"
    delivery_tasks = "https://fleetengine.googleapis.com/v1/providers/${var.project_id}/deliveryTasks"
  }
}

# Google Maps Platform API endpoints
output "maps_api_endpoints" {
  description = "Google Maps Platform API endpoints for routing and navigation"
  value = {
    routes_api = "https://routes.googleapis.com/directions/v2:computeRoutes"
    maps_api   = "https://maps.googleapis.com/maps/api"
  }
}

# Integration commands and examples
output "integration_commands" {
  description = "Commands for integrating with the fleet operations system"
  value = {
    test_fleet_engine_access = "curl -H \"Authorization: Bearer $(gcloud auth print-access-token)\" -H \"Content-Type: application/json\" \"https://fleetengine.googleapis.com/v1/providers/${var.project_id}/vehicles\""
    
    trigger_analytics_job = "gcloud run jobs execute ${google_cloud_run_v2_job.fleet_analytics.name} --region=${var.region} --wait"
    
    query_bigquery_telemetry = "bq query --use_legacy_sql=false 'SELECT vehicle_id, AVG(speed) as avg_speed FROM `${var.project_id}.${var.dataset_name}.vehicle_telemetry` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR) GROUP BY vehicle_id'"
    
    list_bucket_contents = "gsutil ls -r gs://${google_storage_bucket.fleet_data.name}/"
    
    view_firestore_data = var.enable_firestore ? "gcloud firestore collections list --database=${google_firestore_database.fleet_state[0].name}" : "Firestore not enabled"
  }
}

# Cost estimation outputs
output "cost_estimation" {
  description = "Estimated monthly costs for fleet operations (USD)"
  value = {
    note = "Costs vary based on usage patterns and fleet size"
    components = {
      fleet_engine = "Usage-based pricing for API calls and tracking"
      cloud_run_jobs = "Pay-per-use for analytics processing"
      bigquery = "Query and storage costs based on data volume"
      cloud_storage = "Storage and data transfer costs"
      firestore = "Document operations and storage"
      scheduler = "Fixed cost for scheduled jobs"
      monitoring = "Monitoring and alerting costs"
    }
    estimated_range = "50-200 USD/month for moderate fleet size (10-50 vehicles)"
  }
}

# Security and compliance outputs
output "security_configuration" {
  description = "Security configuration details"
  value = {
    service_account_email = google_service_account.fleet_engine_sa.email
    iam_roles = [
      "roles/fleetengine.deliveryFleetReader",
      "roles/fleetengine.deliveryConsumer",
      "roles/bigquery.dataEditor",
      "roles/bigquery.jobUser",
      "roles/storage.objectAdmin",
      "roles/datastore.user",
      "roles/monitoring.metricWriter",
      "roles/logging.logWriter",
      "roles/run.invoker"
    ]
    bucket_uniform_access = google_storage_bucket.fleet_data.uniform_bucket_level_access
    firestore_security_rules = "Configure security rules in Firestore console"
  }
}

# Validation commands
output "validation_commands" {
  description = "Commands to validate the fleet operations deployment"
  value = {
    check_apis_enabled = "gcloud services list --enabled --filter=\"name:(fleetengine.googleapis.com OR run.googleapis.com OR bigquery.googleapis.com OR storage.googleapis.com OR firestore.googleapis.com)\""
    
    verify_service_account = "gcloud iam service-accounts describe ${google_service_account.fleet_engine_sa.email}"
    
    test_bigquery_access = "bq ls ${var.project_id}:${var.dataset_name}"
    
    check_bucket_access = "gsutil ls gs://${google_storage_bucket.fleet_data.name}/"
    
    verify_job_deployment = "gcloud run jobs describe ${google_cloud_run_v2_job.fleet_analytics.name} --region=${var.region}"
    
    check_scheduler_jobs = var.enable_scheduler ? "gcloud scheduler jobs list --location=${var.region}" : "Scheduler not enabled"
    
    view_monitoring_dashboard = var.enable_monitoring ? "Open Google Cloud Console -> Monitoring -> Dashboards" : "Monitoring not enabled"
  }
}

# Next steps and recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    setup_fleet_engine = "Configure Fleet Engine with your vehicle fleet using the provided API endpoints"
    create_sample_data = "Insert sample vehicle telemetry data into BigQuery tables for testing"
    customize_analytics = "Modify the analytics job container to include your specific business logic"
    configure_firestore_rules = "Set up Firestore security rules for your application requirements"
    setup_monitoring_alerts = "Configure additional monitoring alerts based on your operational needs"
    implement_client_apps = "Develop mobile apps and web dashboards using the Fleet Engine APIs"
    optimize_costs = "Review and optimize resource usage based on actual fleet operation patterns"
  }
}